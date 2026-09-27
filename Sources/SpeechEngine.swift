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
    /// Useful common names and command phrases are added before installed app names.
    static var vocabulary: [String] {
        ["Claude", "Claude Code", "Codex", "Opus", "Sonnet", "Jev", "Jev Voice", "ChatGPT", "Chrome", "Google Chrome",
         "Safari", "Finder", "Notes", "Calendar", "Messages", "GitHub", "YouTube", "TypeSafe",
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
            guard self.engine.isRunning else {
                self.cancel(); self.onError?("The audio device stopped or changed. Turn the mic on to reconnect."); return
            }
            let now = Date().timeIntervalSinceReferenceDate
            if let began = self.utterance.beganAt, now - began > (self.sendByWord ? 600 : 120) {
                self.utterance.reset(); self.recorder.reset()
                self.onError?("That request was too long. Nothing was run. Please give a shorter request.")
                self.finishRequest(submit: false)
            } else if self.utterance.discardRequested && now - self.utterance.lastTextAt >= 0.6 {
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
    private func beginRequest() {
        guard active, !suppressed, let recognizer else { return }
        generation += 1
        let token = generation
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
                    self.utterance.recognize(transcription.formattedString, start: start, end: end, at: Date().timeIntervalSinceReferenceDate)
                    if !self.utterance.text.isEmpty { self.consecutiveErrors = 0; self.recorder.markSpeaking() }
                    self.onTranscript?(self.utterance.text)
                    if result.isFinal { self.completeRequest(token: token) }
                } else if let error, !self.ending {
                    let nsError = error as NSError
                    if nsError.domain == "kAFAssistantErrorDomain" && nsError.code == 1110 {
                        self.completeRequest(token: token); return
                    }
                    self.consecutiveErrors += 1
                    if self.consecutiveErrors >= 3 {
                        self.cancel(); self.onError?("The microphone stopped: \(error.localizedDescription)")
                    } else {
                        self.utterance.reset(); self.recorder.reset() // Failed fragments must never execute.
                        self.finishRequest(submit: false)
                    }
                }
            }
        }
        sink.attach(request)
    }
    /// Key released: send what was said, giving the recognizer time to finalize.
    func finishNow() {
        guard active, !ending else { return }
        finishRequest(submit: true, grace: 1.6)
    }
    private func finishRequest(submit: Bool, grace: TimeInterval = 0.3) {
        guard active, !ending, !suppressed else { return }
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
        let audio = submit ? recorder.take() : nil
        if discardAtEnd { recorder.reset() }
        discardAtEnd = false
        beginRequest()
        if submit && !command.isEmpty { deliver(command, audio: audio, sendWords: sendWords) }
    }
    /// Whisper rewrites the finished command from its audio; Apple's text stands in when Whisper
    /// is off, not installed or fails. Commands still arrive in the order they were spoken.
    private func deliver(_ apple: String, audio: Data?, sendWords: Bool) {
        let previous = delivery
        let language = String((UserDefaults.standard.string(forKey: "speechLocale") ?? "en-US").prefix(2))
        delivery = Task { @MainActor [weak self] in
            await previous?.value
            var final = apple
            if let audio, let text = await LocalWhisper.shared.transcribe(audio, language: language) {
                var buffer = UtteranceBuffer(); buffer.sendWords = sendWords; buffer.update(text, at: 0)
                if !buffer.command.isEmpty { final = buffer.command; DebugLog.write("HEARD by Apple: " + apple) }
            }
            self?.onFinished?(final)
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
        sessionGeneration += 1; generation += 1
        active = false; ending = false; suppressed = false; utterance.reset(); recorder.reset()
        timer?.invalidate(); timer = nil; sink.clear(); engine.stop()
        if hasTap { engine.inputNode.removeTap(onBus: 0); hasTap = false }
        task?.cancel(); task = nil; request = nil
        onLevel?(0)
    }
}
