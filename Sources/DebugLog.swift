import Foundation

/// Diagnostic logging is opt-in. It can include screen text and dictated commands.
enum DebugLog {
    private static let queue = DispatchQueue(label: "jev.voice.log")
    private static let stamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return formatter
    }()

    private static var url: URL {
        let appName = Bundle.main.bundleIdentifier ?? "JevVoice"
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return root.appendingPathComponent(appName, isDirectory: true)
            .appendingPathComponent("Logs", isDirectory: true)
            .appendingPathComponent("JevVoice.log")
    }

    static func write(_ message: String) {
        guard UserDefaults.standard.bool(forKey: "diagnosticsEnabled") else { return }
        let line = stamp.string(from: Date()) + "  " + message.replacingOccurrences(of: "\n", with: " ⏎ ") + "\n"
        queue.async {
            let destination = url
            do {
                try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                if let handle = try? FileHandle(forWritingTo: destination) {
                    handle.seekToEndOfFile()
                    handle.write(Data(line.utf8))
                    try? handle.close()
                } else {
                    try Data(line.utf8).write(to: destination, options: .atomic)
                }
            } catch { }
        }
    }

    static func redact(_ secrets: [String]) {
        let items = secrets.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { $0.count >= 3 }
        guard !items.isEmpty else { return }
        queue.async {
            let destination = url
            guard var text = try? String(contentsOf: destination, encoding: .utf8) else { return }
            for secret in items {
                text = text.replacingOccurrences(of: secret, with: "[redacted]", options: .caseInsensitive)
                let digits = secret.filter(\.isNumber)
                if digits.count >= 4, let regex = try? NSRegularExpression(pattern: digits.map(String.init).joined(separator: "[\\s,.\\-]*")) {
                    text = regex.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: "[redacted]")
                }
            }
            try? text.write(to: destination, atomically: true, encoding: .utf8)
        }
    }
}
