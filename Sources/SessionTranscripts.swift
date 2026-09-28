import Foundation
import ApplicationServices

/// Local transcript readers and receipts shared by desktop session actions. No network or model calls.
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
    /// The fallback receipt while saved history lags (a busy task queues new input): the
    /// message shown in the conversation outside any editable field, so a draft never
    /// counts. Pages nested in this one (a browser preview) are skipped. A message of
    /// several paragraphs is matched by its first one, as the page may split them.
    static func shownAsSent(_ text: String, in page: AXUIElement) -> Bool {
        let whole = normalized(text)
        let first = normalized(text.split(whereSeparator: \.isNewline).first.map(String.init) ?? "")
        let expected = first.count >= 20 ? first : whole
        guard !expected.isEmpty else { return false }
        func search(_ element: AXUIElement, _ depth: Int) -> Bool {
            guard depth < 60, (AX.value(element, kAXHiddenAttribute) as? Bool) != true else { return false }
            let role = AX.string(element, kAXRoleAttribute)
            if role == kAXTextAreaRole || role == kAXTextFieldRole || (depth > 0 && role == "AXWebArea") { return false }
            if role == kAXStaticTextRole,
               [AX.string(element, kAXValueAttribute), AX.label(element)].contains(where: { normalized($0).contains(expected) }) { return true }
            return AX.children(element).contains { search($0, depth + 1) }
        }
        return search(page, 0)
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
