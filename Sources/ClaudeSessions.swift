import AppKit
import ApplicationServices

/// Native Claude desktop sessions, opened through the app's own links.
/// New-session links prepare a prompt without submitting it.
enum ClaudeSessions {
    struct Session { let id: String; let cli: String; let title: String; let focused: Double }
    static let bundleID = "com.anthropic.claudefordesktop"

    static var sessionsDirectory: URL {
        if let path = UserDefaults.standard.string(forKey: "claudeSessionsPath"), !path.isEmpty { return URL(fileURLWithPath: path) }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Claude/claude-code-sessions")
    }
    static var projectsDirectory: URL {
        if let path = UserDefaults.standard.string(forKey: "claudeProjectsPath"), !path.isEmpty { return URL(fileURLWithPath: path) }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/projects")
    }
    static func transcriptURL(_ session: Session) -> URL? {
        guard !session.cli.isEmpty else { return nil }
        let folders = (try? FileManager.default.contentsOfDirectory(at: projectsDirectory, includingPropertiesForKeys: nil)) ?? []
        return folders.map { $0.appendingPathComponent(session.cli + ".jsonl") }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
            .max { ((try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast) < ((try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast) }
    }
    static func latestReply(_ session: Session) -> String? {
        transcriptURL(session).flatMap { SessionTranscripts.claudeReply(in: $0) }
    }
    static func continuationURL(_ session: Session) -> URL? {
        var parts = URLComponents(string: "claude://code/continue")!
        parts.queryItems = [URLQueryItem(name: "session", value: session.id)]
        return parts.url
    }
    static func newSessionURL(prompt: String) -> URL? {
        var parts = URLComponents(string: "claude://code/new")!
        parts.queryItems = [URLQueryItem(name: "q", value: String(prompt.prefix(14000)))]
        parts.percentEncodedQuery = parts.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        return parts.url
    }

    /// Sessions that are not archived, most recently focused first.
    static func all() -> [Session] {
        let base = sessionsDirectory
        guard let files = FileManager.default.enumerator(at: base, includingPropertiesForKeys: nil) else { return [] }
        var found: [String: Session] = [:]
        for case let url as URL in files where url.pathExtension == "json" {
            guard let data = try? Data(contentsOf: url), let d = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let id = d["sessionId"] as? String, id.hasPrefix("local_"), (d["isArchived"] as? Bool) != true else { continue }
            let focused = (d["lastFocusedAt"] as? Double) ?? (d["lastActivityAt"] as? Double) ?? 0
            if let old = found[id], old.focused >= focused { continue }
            found[id] = Session(id: id, cli: d["cliSessionId"] as? String ?? "", title: d["title"] as? String ?? "", focused: focused)
        }
        return found.values.sorted { $0.focused > $1.focused }
    }

    /// "focused", an id (desktop or CLI, a prefix is enough) or words from the title.
    /// Inflected word endings differ, so words match by their stem.
    static func find(_ query: String, in supplied: [Session]? = nil) -> Session? {
        let sessions = supplied ?? all()
        let q = query.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if q.isEmpty || q == "focused" { return sessions.first }
        if q.count >= 6, let byID = sessions.first(where: { $0.id.lowercased().hasPrefix(q) || $0.id.lowercased().hasPrefix("local_" + q) || $0.cli.lowercased().hasPrefix(q) }) { return byID }
        if let whole = sessions.first(where: { $0.title.lowercased().contains(q) }) { return whole }
        var stems: [String] = []
        for word in q.split(whereSeparator: { !$0.isLetter && !$0.isNumber }) where word.count >= 3 {
            stems.append(word.count > 5 ? String(word.prefix(word.count - 2)) : String(word))
        }
        guard !stems.isEmpty else { return nil }
        var best: Session?
        var bestScore = 0
        for session in sessions {   // most recently focused first, so ties keep the recent one
            let title = session.title.lowercased()
            let score = stems.filter { title.contains($0) }.count
            if score > bestScore { best = session; bestScore = score }
        }
        return best
    }

    /// Put the session on screen and wait until Claude really shows it.
    static func open(_ session: Session) async throws {
        try Task.checkCancellation()
        guard let url = continuationURL(session), NSWorkspace.shared.open(url) else {
            throw VoiceError.message("Could not open Claude session “\(session.title)”.")
        }
        for _ in 0..<40 {
            if pageOnScreen()?.contains(session.id) == true { DebugLog.write("SESSION: opened «\(session.title)» by link"); return }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        throw VoiceError.message("Claude did not show session “\(session.title)”.")
    }

    /// Open a new session with the prompt already in its box (not sent).
    static func openNew(prompt: String) async throws {
        try Task.checkCancellation()
        guard let url = newSessionURL(prompt: prompt), NSWorkspace.shared.open(url) else { throw VoiceError.message("Could not open a new Claude session.") }
        for _ in 0..<40 {
            if let page = pageOnScreen(), page.contains("/epitaxy"), !page.contains("local_") { DebugLog.write("SESSION: opened a new session by link"); return }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        throw VoiceError.message("Claude did not open a new session.")
    }

    /// Put keyboard focus into the message box of the page on screen. Right after a session
    /// switch the box is not ready yet: at 04:13 on 2026-09-27 a paste 26 ms after the switch
    /// went nowhere and Enter was pressed on an empty box, so the message was lost.
    static func focusComposer() async -> Bool {
        guard !Task.isCancelled else { return false }
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first else { return false }
        let root = AXUIElementCreateApplication(app.processIdentifier)
        for _ in 0..<30 {
            guard !Task.isCancelled else { return false }
            if focusedRole(root) == "AXTextArea" { return true }
            if let box = lastTextArea(root) { AXUIElementSetAttributeValue(box, kAXFocusedAttribute as CFString, kCFBooleanTrue) }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        return !Task.isCancelled && focusedRole(root) == "AXTextArea"
    }

    /// The session whose page is on screen now.
    static func onScreen() -> Session? {
        guard let page = pageOnScreen(), let range = page.range(of: "local_") else { return nil }
        let id = String(page[range.lowerBound...].prefix { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" })
        return all().first { $0.id == id }
    }

    /// A new user message in this session, not a matching older message or tool result.
    static func transcriptHas(_ session: Session, _ text: String, since: Date) -> Bool {
        guard let file = transcriptURL(session) else { return false }
        return SessionTranscripts.hasUserMessage(in: file, text: text, since: since, codex: false)
    }

    /// The session whose saved history got this new message. Split panes and several windows
    /// make "the session on screen" ambiguous, so every transcript written since counts,
    /// unless an expected session was named: then only its history does.
    static func sessionWithMessage(_ text: String, since: Date, expected: Session? = nil) -> Session? {
        if let expected { return transcriptHas(expected, text, since: since) ? expected : nil }
        let sessions = all()
        let folders = (try? FileManager.default.contentsOfDirectory(at: projectsDirectory, includingPropertiesForKeys: nil)) ?? []
        for folder in folders {
            let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
            for file in files where file.pathExtension == "jsonl" && ((try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast) >= since {
                guard SessionTranscripts.hasUserMessage(in: file, text: text, since: since, codex: false) else { continue }
                let cli = file.deletingPathExtension().lastPathComponent
                return sessions.first { $0.cli == cli } ?? Session(id: "", cli: cli, title: "", focused: 0)
            }
        }
        return nil
    }

    /// Saved history lags while a busy session queues new input. The exact message on the
    /// session page with no draft of it left in any message box proves delivery to the app.
    static func messageOnScreen(_ text: String, expected: Session? = nil) -> Bool {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first else { return false }
        let root = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetAttributeValue(root, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        guard let window = AX.element(root, kAXFocusedWindowAttribute) ?? AX.element(root, kAXMainWindowAttribute) else { return false }
        func page(_ element: AXUIElement, _ depth: Int) -> AXUIElement? {
            if AX.string(element, kAXRoleAttribute) == "AXWebArea", let url = AX.value(element, kAXURLAttribute) as? URL,
               url.absoluteString.contains("/epitaxy/local_") { return element }
            guard depth < 14 else { return nil }
            for child in AX.children(element) { if let found = page(child, depth + 1) { return found } }
            return nil
        }
        guard let session = page(window, 0) else { return false }
        if let expected, (AX.value(session, kAXURLAttribute) as? URL)?.absoluteString.contains(expected.id) != true { return false }
        let probe = SessionTranscripts.normalized(text)
        var drafted = false
        func boxes(_ element: AXUIElement, _ depth: Int) {
            guard !drafted, depth < 60 else { return }
            if AX.string(element, kAXRoleAttribute) == kAXTextAreaRole {
                drafted = SessionTranscripts.normalized(AX.string(element, kAXValueAttribute)).contains(probe); return
            }
            for child in AX.children(element) { boxes(child, depth + 1) }
        }
        boxes(session, 0)
        return !probe.isEmpty && !drafted && SessionTranscripts.shownAsSent(text, in: session)
    }

    private static func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
    }
    private static func focusedRole(_ root: AXUIElement) -> String? {
        guard let focused = attribute(root, kAXFocusedUIElementAttribute) else { return nil }
        return attribute(focused as! AXUIElement, kAXRoleAttribute) as? String
    }
    /// The message box is the last text area in the window.
    private static func lastTextArea(_ root: AXUIElement) -> AXUIElement? {
        var found: AXUIElement?
        func search(_ element: AXUIElement, _ depth: Int) {
            if attribute(element, kAXRoleAttribute) as? String == "AXTextArea" { found = element }
            guard depth < 60 else { return }
            for child in (attribute(element, kAXChildrenAttribute) as? [AXUIElement]) ?? [] { search(child, depth + 1) }
        }
        for window in (attribute(root, kAXWindowsAttribute) as? [AXUIElement]) ?? [] { search(window, 0) }
        return found
    }

    /// Address of the page Claude shows ("…/epitaxy/local_…" for a session), read through
    /// Accessibility, or nil when Claude is not running.
    static func pageOnScreen() -> String? {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first else { return nil }
        let root = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetAttributeValue(root, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
            var value: CFTypeRef?
            return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
        }
        func search(_ element: AXUIElement, _ depth: Int) -> String? {
            if let url = attribute(element, kAXURLAttribute) as? URL, url.absoluteString.contains("/epitaxy") { return url.absoluteString }
            guard depth < 14 else { return nil }
            for child in (attribute(element, kAXChildrenAttribute) as? [AXUIElement]) ?? [] {
                if let found = search(child, depth + 1) { return found }
            }
            return nil
        }
        for window in (attribute(root, kAXWindowsAttribute) as? [AXUIElement]) ?? [] {
            if let found = search(window, 0) { return found }
        }
        return nil
    }
}
