import Foundation

/// Read subscription limits through the signed-in CLI, without a model request.
enum CodexAccount {
    static func read(binary: URL? = CodexBrain.binary(), timeout: TimeInterval = 10) async throws -> [String: Any] {
        guard let binary else { throw VoiceError.message("Codex CLI was not found.") }
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                do { continuation.resume(returning: try readSynchronously(binary, timeout: timeout)) }
                catch { continuation.resume(throwing: error) }
            }
        }
    }

    private final class ReaderState: @unchecked Sendable {
        let lock = NSLock(), writeLock = NSLock(), done = DispatchSemaphore(value: 0)
        var result: Result<[String: Any], Error>?
        private var buffer = Data()
        func finish(_ value: Result<[String: Any], Error>) {
            let first = lock.withLock { () -> Bool in
                guard result == nil else { return false }
                result = value; return true
            }
            if first { done.signal() }
        }
        func lines(_ data: Data) -> [Data] {
            lock.withLock {
                buffer.append(data)
                var lines: [Data] = []
                while let newline = buffer.firstIndex(of: 10) {
                    lines.append(Data(buffer[..<newline])); buffer.removeSubrange(...newline)
                }
                return lines
            }
        }
        func send(_ value: [String: Any], to handle: FileHandle) throws {
            try writeLock.withLock { try handle.write(contentsOf: JSONSerialization.data(withJSONObject: value) + Data([10])) }
        }
    }
    private static func readSynchronously(_ binary: URL, timeout: TimeInterval) throws -> [String: Any] {
            let task = Process(), input = Pipe(), output = Pipe()
            task.executableURL = binary
            task.arguments = ["app-server", "--stdio"]
            task.environment = CodexBrain.subscriptionEnvironment()
            task.standardInput = input; task.standardOutput = output; task.standardError = FileHandle.nullDevice
            let state = ReaderState()
            output.fileHandleForReading.readabilityHandler = { reader in
                let data = reader.availableData
                guard !data.isEmpty else { state.finish(.failure(VoiceError.message("Codex usage reader stopped before answering."))); return }
                for line in state.lines(data) {
                    guard let event = try? JSONSerialization.jsonObject(with: line) as? [String: Any], let id = event["id"] as? Int else { continue }
                    if let error = event["error"] as? [String: Any] {
                        state.finish(.failure(VoiceError.message(error["message"] as? String ?? "Codex could not read usage."))); continue
                    }
                    do {
                        if id == 1 {
                            try state.send(["method": "initialized"], to: input.fileHandleForWriting)
                            try state.send(["id": 2, "method": "account/rateLimits/read", "params": NSNull()], to: input.fileHandleForWriting)
                        } else if id == 2, let limits = event["result"] as? [String: Any] { state.finish(.success(limits)) }
                    } catch { state.finish(.failure(error)) }
                }
            }
            defer {
                output.fileHandleForReading.readabilityHandler = nil
                try? input.fileHandleForWriting.close()
                if task.isRunning { task.terminate() }
            }
            try task.run()
            try state.send(["id": 1, "method": "initialize", "params": ["clientInfo": ["name": "conductor", "version": "1.0"], "capabilities": ["experimentalApi": true]]], to: input.fileHandleForWriting)
            guard state.done.wait(timeout: .now() + timeout) == .success, let answer = state.lock.withLock({ state.result }) else {
                throw VoiceError.message("Codex usage could not be read within \(Int(timeout)) seconds.")
            }
            return try answer.get()
    }

    static func summary(_ response: [String: Any]) throws -> String {
        let buckets = response["rateLimitsByLimitId"] as? [String: [String: Any]]
        let limits = buckets?["codex"] ?? response["rateLimits"] as? [String: Any]
        guard let limits else { throw VoiceError.message("Codex did not supply usage limits.") }
        let russian = (UserDefaults.standard.string(forKey: "speechLocale") ?? "en-US").hasPrefix("ru")
        var lines: [String] = []
        for field in ["primary", "secondary"] {
            guard let window = limits[field] as? [String: Any], let used = window["usedPercent"] as? Double, used.isFinite else { continue }
            let minutes = window["windowDurationMins"] as? Int
            let name = minutes == 300 ? (russian ? "Пять часов" : "Five-hour window") : minutes == 10080 ? (russian ? "Неделя" : "Weekly window") : (russian ? "Окно лимита" : "Usage window")
            let left = Int(max(0, min(100, 100 - used)))
            var line = russian ? "\(name): осталось \(left)%." : "\(name): \(left)% remaining."
            if let reset = window["resetsAt"] as? Double {
                let date = DateFormatter(); date.locale = Locale(identifier: russian ? "ru_RU" : "en_US"); date.dateFormat = "MMM d, HH:mm"
                line += russian ? " Сброс \(date.string(from: Date(timeIntervalSince1970: reset)))." : " Resets \(date.string(from: Date(timeIntervalSince1970: reset)))."
            }
            lines.append(line)
        }
        guard !lines.isEmpty else { throw VoiceError.message("Codex usage percentages are unavailable.") }
        return "Codex. " + lines.joined(separator: "\n")
    }
}
