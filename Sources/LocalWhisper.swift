import AVFoundation
import Foundation

/// Optional local final-pass transcription through whisper.cpp. Apple Speech remains the
/// live recognizer and fallback. Paths are configurable in Settings and are never inferred
/// from a developer-specific checkout.
final class LocalWhisper: @unchecked Sendable {
    static let shared = LocalWhisper()
    static let port = 8795
    static let prompt = "Jev Voice, Claude Code, Codex, Chrome, Safari, Finder, YouTube."
    static var binary: String {
        if let configured = UserDefaults.standard.string(forKey: "whisperServerPath"), !configured.isEmpty { return configured }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return [home + "/.local/bin/whisper-server", "/opt/homebrew/bin/whisper-server", "/usr/local/bin/whisper-server"]
            .first { FileManager.default.isExecutableFile(atPath: $0) } ?? ""
    }
    static var model: String {
        if let configured = UserDefaults.standard.string(forKey: "whisperModelPath"), !configured.isEmpty { return configured }
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return support.appendingPathComponent("JevVoice/Models/ggml-large-v3-turbo-q5_0.bin").path
    }
    var enabled: Bool { UserDefaults.standard.object(forKey: "whisperEnabled") as? Bool ?? false }
    var installed: Bool { FileManager.default.isExecutableFile(atPath: Self.binary) && FileManager.default.fileExists(atPath: Self.model) }
    private let lock = NSLock()
    private var process: Process?

    /// Start the server unless one already answers on the port: a rebuild kills Jev Voice but
    /// leaves the server running, and the next start reuses it.
    func start() {
        guard enabled, installed else { return }
        Task.detached(priority: .utility) { [self] in
            if await self.answers() { DebugLog.write("WHISPER: server already running on port \(Self.port)"); return }
            let task = Process()
            task.executableURL = URL(fileURLWithPath: Self.binary)
            let language = String((UserDefaults.standard.string(forKey: "speechLocale") ?? "en-US").prefix(2))
            task.arguments = ["-m", Self.model, "-l", language, "-t", "4", "-nt", "-bo", "1", "--host", "127.0.0.1", "--port", String(Self.port)]
            task.standardOutput = FileHandle.nullDevice; task.standardError = FileHandle.nullDevice
            do {
                try task.run()
                self.lock.withLock { self.process = task }
                DebugLog.write("WHISPER: server started, pid \(task.processIdentifier)")
            } catch { DebugLog.write("WHISPER: could not start the server: \(error.localizedDescription)") }
        }
    }

    /// Free the memory: stop our server and any left over from an earlier run.
    func stop() {
        lock.lock(); let running = process; process = nil; lock.unlock()
        if let running, running.isRunning { running.terminate() }
        let sweep = Process()
        sweep.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
        sweep.arguments = ["-f", "whisper-server .*--port \(Self.port)"]
        try? sweep.run()
        DebugLog.write("WHISPER: server stopped")
    }

    private func answers() async -> Bool {
        var request = URLRequest(url: URL(string: "http://127.0.0.1:\(Self.port)/")!)
        request.timeoutInterval = 0.5
        return (try? await URLSession.shared.data(for: request)) != nil
    }

    /// Whisper's text for 16 kHz mono 16-bit samples, or nil when it is off, not running,
    /// too slow or hears nothing.
    func transcribe(_ samples: Data, language: String) async -> String? {
        guard enabled, installed, samples.count > 16_000 else { return nil }   // under half a second
        let seconds = Double(samples.count) / 32_000
        let boundary = "jev-\(UUID().uuidString)"
        var body = Data()
        func field(_ name: String, _ value: String) { body += Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n".utf8) }
        field("language", language); field("prompt", Self.prompt); field("response_format", "json"); field("temperature", "0.0")
        body += Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"speech.wav\"\r\nContent-Type: audio/wav\r\n\r\n".utf8)
        body += Self.wav(samples) + Data("\r\n--\(boundary)--\r\n".utf8)
        var request = URLRequest(url: URL(string: "http://127.0.0.1:\(Self.port)/inference")!)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 2 + seconds * 0.1
        let start = Date()
        guard let (data, response) = try? await URLSession.shared.upload(for: request, from: body),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let raw = object["text"] as? String else {
            DebugLog.write(String(format: "WHISPER: no answer after %.1fs, Apple's text is used", Date().timeIntervalSince(start)))
            return nil
        }
        let text = Self.clean(raw)
        DebugLog.write(String(format: "WHISPER (%.2fs for %.1fs of audio): ", Date().timeIntervalSince(start), seconds) + text)
        return text.isEmpty ? nil : text
    }

    /// Normalize whitespace in a Whisper transcript.
    static func clean(_ raw: String) -> String {
        var text = raw.replacingOccurrences(of: "\n", with: " ")
        while text.contains("  ") { text = text.replacingOccurrences(of: "  ", with: " ") }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// A 16 kHz mono 16-bit WAV file around raw samples.
    static func wav(_ samples: Data) -> Data {
        var header = Data()
        func le32(_ value: UInt32) { withUnsafeBytes(of: value.littleEndian) { header += $0 } }
        func le16(_ value: UInt16) { withUnsafeBytes(of: value.littleEndian) { header += $0 } }
        header += Data("RIFF".utf8); le32(UInt32(36 + samples.count)); header += Data("WAVE".utf8)
        header += Data("fmt ".utf8); le32(16); le16(1); le16(1); le32(16_000); le32(32_000); le16(2); le16(16)
        header += Data("data".utf8); le32(UInt32(samples.count))
        return header + samples
    }
}

/// The microphone audio of the command being spoken, as 16 kHz mono 16-bit, for Whisper.
/// Until words are heard only the last 1.5 s are kept, so a command never drags minutes of
/// silence along; at most 10 minutes are kept.
final class SpeechRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var samples = Data()
    private var speaking = false
    private var converter: AVAudioConverter?
    private var inputFormat: AVAudioFormat?
    private let output = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16_000, channels: 1, interleaved: true)!

    /// Called from the audio tap's thread.
    func append(_ buffer: AVAudioPCMBuffer) {
        if converter == nil || inputFormat != buffer.format {
            inputFormat = buffer.format
            converter = AVAudioConverter(from: buffer.format, to: output)
        }
        guard let converter, buffer.frameLength > 0 else { return }
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * 16_000 / buffer.format.sampleRate) + 64
        guard let converted = AVAudioPCMBuffer(pcmFormat: output, frameCapacity: capacity) else { return }
        var fed = false
        var error: NSError?
        converter.convert(to: converted, error: &error) { _, status in
            if fed { status.pointee = .noDataNow; return nil }
            fed = true; status.pointee = .haveData; return buffer
        }
        guard error == nil, converted.frameLength > 0, let channel = converted.int16ChannelData?[0] else { return }
        let bytes = Data(bytes: channel, count: Int(converted.frameLength) * 2)
        lock.lock()
        samples += bytes
        let limit = speaking ? 16_000 * 2 * 600 : 48_000
        if samples.count > limit { samples.removeFirst(samples.count - limit) }
        lock.unlock()
    }
    /// Words were heard: keep everything from now until the command is taken.
    func markSpeaking() { lock.lock(); speaking = true; lock.unlock() }
    /// The command's audio; the recorder starts over.
    func take() -> Data { lock.lock(); let taken = samples; samples = Data(); speaking = false; lock.unlock(); return taken }
    func reset() { lock.lock(); samples = Data(); speaking = false; lock.unlock() }
}
