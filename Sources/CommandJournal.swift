import Foundation

/// Local diagnostic files contain private command data, so persistence is opt-in.
final class DiagnosticFiles {
    static let shared = DiagnosticFiles()
    let directory: URL
    private let enabled: () -> Bool
    private let queue = DispatchQueue(label: "conductor.command-journal")

    init(directory: URL? = nil, enabled: @escaping () -> Bool = { UserDefaults.standard.bool(forKey: "diagnosticsEnabled") }) {
        self.directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent(Bundle.main.bundleIdentifier ?? "Conductor", isDirectory: true)
            .appendingPathComponent("Logs", isDirectory: true)
        self.enabled = enabled
    }
    func append(_ entry: [String: Any], to name: String) {
        guard enabled(), JSONSerialization.isValidJSONObject(entry),
              let data = try? JSONSerialization.data(withJSONObject: entry, options: [.sortedKeys]) else { return }
        let line = data + Data([0x0a])
        queue.async { [self] in
            guard enabled() else { return }
            do {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
                let file = directory.appendingPathComponent(name)
                if !FileManager.default.fileExists(atPath: file.path) {
                    guard FileManager.default.createFile(atPath: file.path, contents: nil, attributes: [.posixPermissions: 0o600]) else { return }
                }
                let handle = try FileHandle(forWritingTo: file)
                defer { try? handle.close() }
                try handle.seekToEnd(); try handle.write(contentsOf: line)
            } catch { /* Diagnostic failures do not block a user command. */ }
        }
    }
    func recentEntries() -> [[String: Any]] {
        guard enabled() else { return [] }
        return queue.sync {
            guard let handle = try? FileHandle(forReadingFrom: directory.appendingPathComponent("journal.jsonl")) else { return [] }
            defer { try? handle.close() }
            let length = (try? handle.seekToEnd()) ?? 0
            try? handle.seek(toOffset: length > 60_000 ? length - 60_000 : 0)
            return String(decoding: handle.readDataToEndOfFile(), as: UTF8.self).split(separator: "\n").compactMap {
                (try? JSONSerialization.jsonObject(with: Data($0.utf8))) as? [String: Any]
            }
        }
    }
    func flush() { queue.sync {} }
}

/// Sanitize values before JSON encoding, including secrets containing quotes or newlines.
enum DiagnosticRedaction {
    static func clean(_ value: Any, secrets: [String]) -> Any {
        let mirror = Mirror(reflecting: value)
        if mirror.displayStyle == .optional { return mirror.children.first.map { clean($0.value, secrets: secrets) } ?? NSNull() }
        if let text = value as? String {
            return secrets.filter { !$0.isEmpty }.reduce(text) { result, secret in
                var clean = result.replacingOccurrences(of: secret, with: "[redacted]", options: .caseInsensitive)
                let digits = secret.filter(\.isNumber)
                if digits.count >= 4, let regex = try? NSRegularExpression(pattern: digits.map(String.init).joined(separator: "[\\s,.\\-]*")) {
                    clean = regex.stringByReplacingMatches(in: clean, range: NSRange(clean.startIndex..., in: clean), withTemplate: "[redacted]")
                }
                return clean
            }
        }
        if let dictionary = value as? [String: Any] { return dictionary.mapValues { clean($0, secrets: secrets) } }
        if let array = value as? [Any] { return array.map { clean($0, secrets: secrets) } }
        return value
    }
}

enum ProblemLog {
    static func report(_ problem: String, command: String, source: String, files: DiagnosticFiles = .shared) {
        files.append(["time": ISO8601DateFormatter().string(from: Date()), "source": source,
                      "problem": problem, "command": command], to: "problems.jsonl")
    }
}

enum ToolWishes {
    static func add(_ wish: String, command: String, files: DiagnosticFiles = .shared) {
        files.append(["time": ISO8601DateFormatter().string(from: Date()), "wish": wish, "command": command], to: "tool-wishes.jsonl")
    }
}

/// Switching brains keeps recent work in memory even when disk diagnostics are off.
/// An intentional reset sets a local time boundary so old files cannot restore it.
final class CommandJournal {
    private let files: DiagnosticFiles
    private let defaults: UserDefaults
    private var recent: [[String: Any]] = []
    private static let resetKey = "commandContextResetAt"

    init(files: DiagnosticFiles = .shared, defaults: UserDefaults = .standard) {
        self.files = files; self.defaults = defaults
        let boundary = defaults.double(forKey: Self.resetKey)
        recent = files.recentEntries().filter {
            ($0["epoch"] as? Double ?? 0) > boundary && $0["command"] is String
                && !(($0["outcome"] as? String ?? "").hasPrefix("reset"))
        }
        recent = Array(recent.suffix(6))
    }
    func record(_ entry: [String: Any], secrets: [String]) {
        guard let clean = DiagnosticRedaction.clean(entry, secrets: secrets) as? [String: Any] else { return }
        let outcome = clean["outcome"] as? String ?? ""
        if !outcome.hasPrefix("reset"), (clean["epoch"] as? Double ?? 0) > defaults.double(forKey: Self.resetKey) {
            recent.append(clean); recent = Array(recent.suffix(6))
        }
        files.append(clean, to: "journal.jsonl")
        let command = clean["command"] as? String ?? ""
        for problem in clean["problems"] as? [String] ?? [] {
            ProblemLog.report(problem, command: command, source: "brain", files: files)
        }
        if let error = clean["error"] as? String {
            ProblemLog.report(error, command: command, source: "command", files: files)
        }
        for wish in clean["missing_tools"] as? [String] ?? [] { ToolWishes.add(wish, command: command, files: files) }
        for report in clean["agent_errors"] as? [[String: String]] ?? [] {
            files.append(["time": clean["time"] ?? "", "command": command, "report": report], to: "agent-errors.jsonl")
        }
    }
    func reset(at date: Date = Date()) {
        recent.removeAll()
        // The timestamp contains no command text and is not a diagnostic log.
        defaults.set(date.timeIntervalSince1970, forKey: Self.resetKey)
    }
    func summary() -> String {
        recent.map { entry in
            let command = entry["command"] as? String ?? ""
            let answer = (entry["answer"] as? String) ?? (entry["outcome"] as? String ?? "")
            let outcome = entry["outcome"] as? String ?? "unknown"
            return "\(String(command.prefix(240))) → [\(outcome)] \(String(answer.prefix(240)))"
        }.joined(separator: "\n")
    }
}
