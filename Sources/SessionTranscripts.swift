import Foundation

/// Local transcript readers shared by desktop session actions. No network or model calls.
enum SessionTranscripts {
    static func events(in file: URL, tailBytes: UInt64? = nil, _ visit: ([String: Any]) -> Void) {
        guard let handle = try? FileHandle(forReadingFrom: file) else { return }
        defer { try? handle.close() }
        if let tailBytes {
            let size = (try? handle.seekToEnd()) ?? 0
            try? handle.seek(toOffset: size > tailBytes ? size - tailBytes : 0)
        }
        var pending = Data()
        while let chunk = try? handle.read(upToCount: 64 * 1024), !chunk.isEmpty {
            pending.append(chunk)
            while let end = pending.firstIndex(of: 10) {
                let line = Data(pending[..<end]); pending.removeSubrange(...end)
                if let event = try? JSONSerialization.jsonObject(with: line) as? [String: Any] { visit(event) }
            }
        }
        if !pending.isEmpty, let event = try? JSONSerialization.jsonObject(with: pending) as? [String: Any] { visit(event) }
    }
    static func text(_ content: Any?, kinds: Set<String>) -> String {
        if let plain = content as? String { return plain }
        return (content as? [[String: Any]] ?? []).compactMap { block in
            kinds.contains(block["type"] as? String ?? "") ? block["text"] as? String : nil
        }.joined(separator: "\n")
    }
    static func normalized(_ text: String) -> String {
        var body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if (body.hasPrefix("[Jev") || body.hasPrefix("[Conductor")), let close = body.firstIndex(of: "]") { body = String(body[body.index(after: close)...]) }
        return body.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
    static func timestamp(_ raw: Any?) -> Date? {
        guard let text = raw as? String else { return nil }
        let fractional = ISO8601DateFormatter(); fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: text) ?? ISO8601DateFormatter().date(from: text)
    }
    static func hasUserMessage(in file: URL, text expected: String, since: Date, codex: Bool) -> Bool {
        let probe = normalized(expected)
        guard !probe.isEmpty else { return false }
        var found = false
        events(in: file, tailBytes: 400_000) { event in
            guard !found, event["isSidechain"] as? Bool != true,
                  let time = timestamp(event["timestamp"]), time >= since else { return }
            let message: [String: Any]
            if codex {
                guard event["type"] as? String == "response_item",
                      let payload = event["payload"] as? [String: Any], payload["role"] as? String == "user" else { return }
                message = payload
            } else {
                guard event["type"] as? String == "user", let payload = event["message"] as? [String: Any] else { return }
                message = payload
            }
            let actual = text(message["content"], kinds: ["text", "input_text"])
            found = normalized(actual).contains(probe)
        }
        return found
    }
    static func claudeReply(in file: URL) -> String? {
        var turn: [String] = [], finished = "", done = true
        events(in: file) { event in
            guard event["isSidechain"] as? Bool != true, let message = event["message"] as? [String: Any] else { return }
            let body = text(message["content"], kinds: ["text"])
            if event["type"] as? String == "user", !body.isEmpty {
                if !turn.isEmpty, done { finished = turn.joined(separator: "\n\n") }
                turn = []; done = false
            } else if event["type"] as? String == "assistant" {
                if !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { turn.append(body) }
                done = message["stop_reason"] as? String == "end_turn"
            }
        }
        let current = turn.joined(separator: "\n\n")
        if done { return current.isEmpty ? nil : current }
        let note = "The agent is still working. Its text so far: " + (current.isEmpty ? "none" : current)
        return finished.isEmpty ? note : finished + "\n\n" + note
    }
    static func codexReply(in file: URL) -> String? {
        var reply: String?
        events(in: file) { event in
            guard let payload = event["payload"] as? [String: Any], payload["role"] as? String == "assistant" else { return }
            let body = text(payload["content"], kinds: ["output_text", "text"]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !body.isEmpty { reply = body }
        }
        return reply
    }
}
