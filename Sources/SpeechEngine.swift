import Foundation
import Speech
import AVFoundation

// The audio tap stays open for the whole session. Recognition requests rotate
// between utterances while Jev and Mac actions run independently.
private final class SpeechBufferSink {
    private let lock = NSLock()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var pending: [AVAudioPCMBuffer] = []
    private var buffering = false
    func attach(_ next: SFSpeechAudioBufferRecognitionRequest) {
        lock.lock(); defer { lock.unlock() }
        request = next
        for buffer in pending { next.append(buffer) }
        pending.removeAll(); buffering = false
    }
    func betweenUtterances() {
        lock.lock(); defer { lock.unlock() }
        request = nil; buffering = true
    }
    func clear() {
        lock.lock(); defer { lock.unlock() }
        request = nil; buffering = false; pending.removeAll()
    }
    func append(_ buffer: AVAudioPCMBuffer) {
        lock.lock(); defer { lock.unlock() }
        if let request { request.append(buffer); return }
        // Keep preroll during finalization so a quick follow-up isn't lost.
        guard buffering, pending.count < 80,
              let copy = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: buffer.frameLength) else { return }
        copy.frameLength = buffer.frameLength
        let input = UnsafeMutableAudioBufferListPointer(buffer.mutableAudioBufferList)
        let output = UnsafeMutableAudioBufferListPointer(copy.mutableAudioBufferList)
        for (source, target) in zip(input, output) {
            if let src = source.mData, let dst = target.mData {
                memcpy(dst, src, Int(min(source.mDataByteSize, target.mDataByteSize)))
            }
        }
        pending.append(copy)
    }
}

final class SpeechEngine {
    var onTranscript: ((String) -> Void)?
    var onLevel: ((Double) -> Void)?
    var onFinished: ((String) -> Void)?
    var onError: ((String) -> Void)?
    /// Recognition stopped before submission. Keep this draft for explicit review.
    var onInterrupted: ((String, String) -> Void)?
    var onDiagnostic: ((String) -> Void)?
    /// Word mode: text discarded by an explicit discard phrase.
    var onDiscarded: ((String) -> Void)?
    private let engine = AVAudioEngine()
    // The speech language is selected in Settings. English is the first-run default.
    static func makeRecognizer() -> SFSpeechRecognizer? { SFSpeechRecognizer(locale: Locale(identifier: UserDefaults.standard.string(forKey: "speechLocale") ?? "en-US")) }
    private var recognizer = SpeechEngine.makeRecognizer()
    private let sink = SpeechBufferSink()
    /// The command's audio for Whisper (LocalWhisper.swift), recorded alongside Apple's recognizer.
    private let recorder = SpeechRecorder()
    private var delivery: Task<Void, Never>?
    private var pendingDeliveries = 0
    var finishingSubmission: Bool { (ending && submitAtEnd) || pendingDeliveries > 0 }
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var timer: Timer?
    private var utterance = UtteranceBuffer()
    private var requestStartedAt = Date()
    private var active = false
    private var ending = false
    private var submitAtEnd = false
    private var suppressed = false
    private var generation = 0
    private var sessionGeneration = 0
    private var hasTap = false
    private var hints: [String] = []
    private var consecutiveErrors = 0
    private var replayTask: Task<Void, Never>?
    private var replaying = false
    /// Useful common names and command phrases are added before installed app names.
    static var vocabulary: [String] {
        ["Claude", "Claude Code", "Codex", "Opus", "Sonnet", "Jev", "Conductor", "ChatGPT", "Chrome", "Google Chrome",
         "Safari", "Finder", "Notes", "Calendar", "Messages", "GitHub", "YouTube", "TypeSafe",
         "Astra", "Luna", "Terra", "Muse", "Jev Voice", "Hermes", "Roblox", "Roblox Studio", "Obsidian", "Freeform", "Telegram", "LinkedIn", "Meshy", "NanoGPT",
         "end command", "cancel task", "stop listening"] + VoiceLocalization.words("speech.vocabulary")
    }
    /// Hold-to-talk: the key release ends the request, not a pause in speech.
    var manualEndpoint = false
    /// Word mode waits for an explicit end phrase or a key tap.
    var sendByWord = false { didSet { utterance.sendWords = sendByWord } }
    private var discardAtEnd = false
    var isLocalAvailable: Bool { recognizer?.supportsOnDeviceRecognition == true }
    var microphoneGranted: Bool { AVCaptureDevice.authorizationStatus(for: .audio) == .authorized }
    var speechGranted: Bool { SFSpeechRecognizer.authorizationStatus() == .authorized }

    func requestPermissions() async -> Bool {
        let microphone = await AVCaptureDevice.requestAccess(for: .audio)
        let speech = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0 == .authorized) }
        }
        return microphone && speech
    }
    func start(hints: [String]) throws {
        guard microphoneGranted && speechGranted else { throw VoiceError.message("Enable Microphone and Speech Recognition in Setup first.") }
        recognizer = Self.makeRecognizer()
        guard let recognizer, recognizer.isAvailable else { throw VoiceError.message("Apple speech recognition is currently unavailable.") }
        cancel()
        active = true; suppressed = false; consecutiveErrors = 0
        let vocabulary = Self.vocabulary
        self.hints = Array((vocabulary + hints.filter { !vocabulary.contains($0) }).prefix(100))
        let session = sessionGeneration
        let node = engine.inputNode
        let format = node.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { cancel(); throw VoiceError.message("No working microphone was found.") }
        beginRequest()
        node.installTap(onBus: 0, bufferSize: 512, format: format) { [weak self, sink, recorder] buffer, _ in
            sink.append(buffer)
            recorder.append(buffer)
            guard let samples = buffer.floatChannelData?[0] else { return }
            let count = Int(buffer.frameLength)
            guard count > 0 else { return }
            var sum: Float = 0
            for index in 0..<count { sum += samples[index] * samples[index] }
            let rms = Double(sqrt(sum / Float(count)))
            DispatchQueue.main.async {
                guard let self, self.active, !self.suppressed, session == self.sessionGeneration else { return }
                self.onLevel?(min(1, rms * 12))
                if rms > 0.012 {
                    self.utterance.voice(at: Date().timeIntervalSinceReferenceDate)
                    // The endpoint was already decided after a complete phrase;
                    // resumed audio stays buffered for the next request.
                }
            }
        }
        hasTap = true
        engine.prepare()
        do { try engine.start() } catch { cancel(); throw error }
        startTimer()
    }
    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { [weak self] _ in
            guard let self, self.active, !self.ending, !self.suppressed else { return }
            guard self.replaying || self.engine.isRunning else {
                self.interruptRecognition("The audio device stopped or changed. Turn the mic on to reconnect."); return
            }
            let now = Date().timeIntervalSinceReferenceDate
            if self.utterance.discardRequested && now - self.utterance.lastTextAt >= 0.6 {
                let dropped = self.utterance.text
                self.discardAtEnd = true
                self.finishRequest(submit: false)
                self.onDiscarded?(dropped)
            } else if (!self.manualEndpoint || self.utterance.explicitEnd) && self.utterance.shouldFinish(at: now) {
                self.finishRequest(submit: true)
            } else if Date().timeIntervalSince(self.requestStartedAt) > 25 {
                self.finishRequest(submit: false)
            }
        }
    }
    /// Feed a real recording at its original pace through the exact same
    /// recognizer, audio-level endpoint logic, request rotation and callbacks.
    /// This diagnostic mode never mixes the recording with the live microphone.
    func replay(_ url: URL, finished: @escaping () -> Void) throws {
        guard speechGranted else { throw VoiceError.message("Speech Recognition is not authorized for this app process (status \(SFSpeechRecognizer.authorizationStatus().rawValue)).") }
        guard isLocalAvailable else { throw VoiceError.message("On-device speech recognition is unavailable for the selected language.") }
        cancel()
        let file = try AVAudioFile(forReading: url)
        active = true; replaying = true
        hints = Self.vocabulary
        beginRequest(); startTimer()
        replayTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let start = Date()
                while file.framePosition < file.length {
                    try Task.checkCancellation()
                    guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 1024) else { throw VoiceError.message("Cannot allocate audio buffer.") }
                    try file.read(into: buffer)
                    self.sink.append(buffer)
                    if let samples = buffer.floatChannelData?[0], buffer.frameLength > 0 {
                        var sum: Float = 0
                        for index in 0..<Int(buffer.frameLength) { sum += samples[index] * samples[index] }
                        let rms = Double(sqrt(sum / Float(buffer.frameLength)))
                        self.onLevel?(min(1, rms * 12))
                        if rms > 0.012 {
                            self.utterance.voice(at: Date().timeIntervalSinceReferenceDate)
                            // New audio is queued for the next utterance after an endpoint.
                        }
                    }
                    let due = Double(file.framePosition) / file.processingFormat.sampleRate
                    let delay = due - Date().timeIntervalSince(start)
                    if delay > 0 { try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) }
                }
                try await Task.sleep(nanoseconds: 3_200_000_000)
                self.timer?.invalidate(); self.timer = nil
                self.active = false; self.replaying = false
                self.generation += 1; self.sink.clear(); self.task?.cancel(); self.task = nil
                self.onLevel?(0); finished()
            } catch is CancellationError { }
            catch { self.onError?(error.localizedDescription) }
        }
    }
    private func beginRequest() {
        guard active, !suppressed, let recognizer else { return }
        generation += 1
        let token = generation
        onDiagnostic?("begin request \(generation)")
        ending = false; submitAtEnd = false; requestStartedAt = Date()
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition
        request.shouldReportPartialResults = true
        request.taskHint = .dictation
        request.addsPunctuation = true
        request.contextualStrings = hints
        self.request = request
        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            DispatchQueue.main.async {
                guard let self, self.active, !self.suppressed, token == self.generation else { return }
                if let result {
                    let transcription = result.bestTranscription
                    let start = transcription.segments.first?.timestamp
                    let end = transcription.segments.last.map { $0.timestamp + $0.duration }
                    self.onDiagnostic?("span \(token): \(start ?? -1)...\(end ?? -1)")
                    self.utterance.recognize(transcription.formattedString, start: start, end: end, at: Date().timeIntervalSinceReferenceDate)
                    if !transcription.formattedString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        self.consecutiveErrors = 0; self.recorder.markSpeaking()
                    }
                    self.onTranscript?(self.utterance.text)
                    if result.isFinal { self.onDiagnostic?("final \(token): \(result.bestTranscription.formattedString)"); self.completeRequest(token: token) }
                } else if let error, !self.ending {
                    let nsError = error as NSError
                    self.onDiagnostic?("error \(token): \(nsError.domain)/\(nsError.code); buffered: \(self.utterance.text)")
                    if nsError.domain == "kAFAssistantErrorDomain" && nsError.code == 1110 {
                        self.completeRequest(token: token); return
                    }
                    self.consecutiveErrors += 1
                    if self.consecutiveErrors >= 3 {
                        self.interruptRecognition("Speech recognition stopped: \(error.localizedDescription)")
                    } else {
                        // Retain already recognized words across a recoverable request failure.
                        // Rotation does not submit them; the user still decides when to finish.
                        self.utterance.commitSegment()
                        self.finishRequest(submit: false)
                    }
                }
            }
        }
        sink.attach(request)
    }
    /// Key released: send what was said, giving the recognizer time to finalize.
    func finishNow() {
        guard active else { return }
        if ending {
            // Fn can be released while the 25-second rotation is finalizing.
            // Upgrade that rotation to submission instead of dropping the release.
            submitAtEnd = true
            return
        }
        finishRequest(submit: true, grace: 1.6)
    }
    private func finishRequest(submit: Bool, grace: TimeInterval = 0.3) {
        guard active, !ending, !suppressed else { return }
        onDiagnostic?("finish request \(generation), submit=\(submit), text=\(utterance.text)")
        ending = true; submitAtEnd = submit
        sink.betweenUtterances(); request?.endAudio()
        let token = generation
        DispatchQueue.main.asyncAfter(deadline: .now() + grace) { [weak self] in self?.completeRequest(token: token) }
    }
    private func completeRequest(token: Int) {
        guard active, !suppressed, token == generation else { return }
        utterance.commitSegment()
        let submit = submitAtEnd
        let command = utterance.command
        let sendWords = utterance.sendWords
        generation += 1
        sink.betweenUtterances(); task?.cancel(); task = nil; request = nil
        if submit || discardAtEnd { utterance.reset() }
        let audio = submit ? recorder.takeForTranscription() : nil
        if discardAtEnd { recorder.reset() }
        discardAtEnd = false
        beginRequest()
        if submit && !command.isEmpty { deliver(command, audio: audio, sendWords: sendWords) }
    }
    /// Whisper rewrites the finished command from its audio; Apple's text stands in when Whisper
    /// is off, not installed or fails. Commands still arrive in the order they were spoken.
    private func deliver(_ apple: String, audio: Data?, sendWords: Bool) {
        let previous = delivery
        let session = sessionGeneration
        pendingDeliveries += 1
        let language = String((UserDefaults.standard.string(forKey: "speechLocale") ?? "en-US").prefix(2))
        delivery = Task { @MainActor [weak self] in
            await previous?.value
            guard let self, session == self.sessionGeneration, !Task.isCancelled else { return }
            var final = apple
            if let audio, let text = await LocalWhisper.shared.transcribe(audio, language: language) {
                var buffer = UtteranceBuffer(); buffer.sendWords = sendWords; buffer.update(text, at: 0)
                if !buffer.command.isEmpty { final = buffer.command; DebugLog.write("HEARD by Apple: " + apple) }
            }
            guard session == self.sessionGeneration, !Task.isCancelled else { return }
            self.pendingDeliveries -= 1
            self.onDiagnostic?("submit: \(final)")
            self.onFinished?(final)
        }
    }
    /// Keep the physical microphone open, but exclude our own spoken feedback.
    func suppressRecognition(_ value: Bool) {
        guard suppressed != value else { return }
        suppressed = value
        if value { onLevel?(0) }
        generation += 1; task?.cancel(); task = nil; request = nil
        sink.clear(); utterance.reset(); recorder.reset(); ending = false
        if active && !value { beginRequest() }
    }
    func cancel() {
        delivery?.cancel(); delivery = nil; pendingDeliveries = 0
        replayTask?.cancel(); replayTask = nil; replaying = false
        sessionGeneration += 1; generation += 1
        active = false; ending = false; suppressed = false; utterance.reset(); recorder.reset()
        timer?.invalidate(); timer = nil; sink.clear(); engine.stop()
        if hasTap { engine.inputNode.removeTap(onBus: 0); hasTap = false }
        task?.cancel(); task = nil; request = nil
        onLevel?(0)
    }
    private func interruptRecognition(_ message: String) {
        let draft = utterance.command
        cancel()
        if !draft.isEmpty { onInterrupted?(draft, message) }
        else { onError?(message) }
    }
}
