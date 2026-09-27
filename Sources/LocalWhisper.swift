import AVFoundation
import Darwin
import Foundation

/// Optional local final-pass transcription through whisper.cpp. Apple Speech remains the
/// live recognizer and fallback. Paths are configurable in Settings and are never inferred
/// from a developer-specific checkout.
final class LocalWhisper: @unchecked Sendable {
    static let shared = LocalWhisper()
    static let prompt = "Conductor, Claude Code, Codex, Chrome, Safari, Finder, YouTube."
    static var binary: String {
        if let configured = UserDefaults.standard.string(forKey: "whisperServerPath"), !configured.isEmpty { return configured }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return [home + "/.local/bin/whisper-server", "/opt/homebrew/bin/whisper-server", "/usr/local/bin/whisper-server"]
            .first { FileManager.default.isExecutableFile(atPath: $0) } ?? ""
    }
    static var model: String {
        if let configured = UserDefaults.standard.string(forKey: "whisperModelPath"), !configured.isEmpty { return configured }
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return support.appendingPathComponent("Conductor/Models/ggml-large-v3-turbo-q5_0.bin").path
    }
    var enabled: Bool { UserDefaults.standard.object(forKey: "whisperEnabled") as? Bool ?? false }
    var installed: Bool { FileManager.default.isExecutableFile(atPath: Self.binary) && FileManager.default.fileExists(atPath: Self.model) }
    private let lock = NSLock()
    private var process: Process?
    private var port: Int?
    private var starting = false
    private var startGeneration = 0

    /// Ask the OS for an unused loopback port. Each app process starts its own server.
    private static func availablePort() -> Int? {
        let socketFD = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        guard socketFD >= 0 else { return nil }
        defer { Darwin.close(socketFD) }
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = 0
        address.sin_addr = in_addr(s_addr: in_addr_t(INADDR_LOOPBACK).bigEndian)
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(socketFD, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bound == 0 else { return nil }
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let found = withUnsafeMutablePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.getsockname(socketFD, $0, &length)
            }
        }
        guard found == 0 else { return nil }
        return Int(UInt16(bigEndian: address.sin_port))
    }

    /// A successful HTTP connection alone does not prove the response came from
    /// this app's server. Check that its PID owns the listening socket first.
    private static func ownsListeningPort(_ port: Int, pid: Int32) -> Bool {
        let binary = "/usr/sbin/lsof"
        guard FileManager.default.isExecutableFile(atPath: binary) else { return false }
        let check = Process()
        check.executableURL = URL(fileURLWithPath: binary)
        check.arguments = ["-nP", "-a", "-p", String(pid), "-iTCP:\(port)", "-sTCP:LISTEN", "-F", "p"]
        let output = Pipe()
        check.standardOutput = output
        check.standardError = FileHandle.nullDevice
        do {
            try check.run()
            let data = output.fileHandleForReading.readDataToEndOfFile()
            check.waitUntilExit()
            guard check.terminationStatus == 0, let text = String(data: data, encoding: .utf8) else { return false }
            return text.split(separator: "\n").contains(Substring("p\(pid)"))
        } catch { return false }
    }

    private static func answersOnPort(_ port: Int) async -> Bool {
        var request = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/")!)
        request.timeoutInterval = 0.5
        return (try? await URLSession.shared.data(for: request)) != nil
    }

    /// Start only a server owned by this app process; never attach to another app's port.
    func start() {
        guard enabled, installed else { return }
        let token = lock.withLock { () -> Int? in
            if starting || process?.isRunning == true { return nil }
            process = nil; port = nil
            startGeneration += 1; starting = true
            return startGeneration
        }
        guard let token else { return }
        Task.detached(priority: .utility) { [self] in
            guard let port = Self.availablePort() else {
                self.lock.withLock { if token == self.startGeneration { self.starting = false } }
                DebugLog.write("WHISPER: could not reserve a local port")
                return
            }
            let task = Process()
            task.executableURL = URL(fileURLWithPath: Self.binary)
            let language = String((UserDefaults.standard.string(forKey: "speechLocale") ?? "en-US").prefix(2))
            task.arguments = ["-m", Self.model, "-l", language, "-t", "4", "-nt", "-bo", "1", "--host", "127.0.0.1", "--port", String(port)]
            task.standardOutput = FileHandle.nullDevice; task.standardError = FileHandle.nullDevice
            do {
                try task.run()
                let accepted = self.lock.withLock { () -> Bool in
                    guard token == self.startGeneration else { return false }
                    self.process = task
                    return true
                }
                guard accepted else {
                    if task.isRunning { task.terminate() }
                    return
                }
                let deadline = Date().addingTimeInterval(25)
                var ready = false
                while Date() < deadline, task.isRunning {
                    let current = self.lock.withLock { token == self.startGeneration && self.process === task }
                    if !current { break }
                    if Self.ownsListeningPort(port, pid: task.processIdentifier),
                       await Self.answersOnPort(port),
                       task.isRunning,
                       Self.ownsListeningPort(port, pid: task.processIdentifier) {
                        ready = true
                        break
                    }
                    try? await Task.sleep(nanoseconds: 500_000_000)
                }
                let published = self.lock.withLock { () -> Bool in
                    guard token == self.startGeneration, self.process === task else { return false }
                    self.starting = false
                    if ready { self.port = port; return true }
                    self.process = nil
                    return false
                }
                if published { DebugLog.write("WHISPER: server ready, pid \(task.processIdentifier), port \(port)") }
                else {
                    if task.isRunning { task.terminate() }
                    if accepted { DebugLog.write("WHISPER: server did not become ready; Apple's text is used") }
                }
            } catch {
                self.lock.withLock { if token == self.startGeneration { self.starting = false } }
                DebugLog.write("WHISPER: could not start the server: \(error.localizedDescription)")
            }
        }
    }

    /// Free the memory by stopping only the server this process started.
    func stop() {
        let running = lock.withLock { () -> Process? in
            startGeneration += 1; starting = false
            let running = process; process = nil; port = nil
            return running
        }
        if let running, running.isRunning { running.terminate() }
        DebugLog.write("WHISPER: server stopped")
    }

    /// Wait for this process's verified server before a diagnostic request.
    func waitUntilReady(timeout: TimeInterval) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if lock.withLock({ process?.isRunning == true && port != nil }) { return true }
            try? await Task.sleep(nanoseconds: 250_000_000)
        }
        return false
    }

    /// Whisper's text for 16 kHz mono 16-bit samples, or nil when it is off, not running,
    /// too slow or hears nothing.
    func transcribe(_ samples: Data, language: String) async -> String? {
        guard enabled, installed, samples.count > 16_000 else { return nil }   // under half a second
        guard let (port, pid) = lock.withLock({ () -> (Int, Int32)? in
            guard let process, process.isRunning, let port else { return nil }
            return (port, process.processIdentifier)
        }), Self.ownsListeningPort(port, pid: pid) else { return nil }
        let seconds = Double(samples.count) / 32_000
        let boundary = "jev-\(UUID().uuidString)"
        var body = Data()
        func field(_ name: String, _ value: String) { body += Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n".utf8) }
        field("language", language); field("prompt", Self.prompt); field("response_format", "json"); field("temperature", "0.0")
        body += Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"speech.wav\"\r\nContent-Type: audio/wav\r\n\r\n".utf8)
        body += Self.wav(samples) + Data("\r\n--\(boundary)--\r\n".utf8)
        var request = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/inference")!)
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
