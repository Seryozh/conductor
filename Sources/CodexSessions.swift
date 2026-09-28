import AppKit
import ApplicationServices

/// Native Codex desktop threads. Links prepare new prompts without submitting them.
enum CodexSessions {
    struct Thread { let id: String; let title: String; let updated: String }
    static let bundleID = "com.openai.codex"
    static var home: URL {
        if let path = UserDefaults.standard.string(forKey: "codexHomePath"), !path.isEmpty { return URL(fileURLWithPath: path) }
        if let path = ProcessInfo.processInfo.environment["CODEX_HOME"], !path.isEmpty { return URL(fileURLWithPath: path) }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex")
    }
    static func continuationURL(_ thread: Thread) -> URL? { URL(string: "codex://threads/" + thread.id) }
    static func newThreadURL(prompt: String) -> URL? {
        var parts = URLComponents(string: "codex://threads/new")!
        parts.queryItems = [URLQueryItem(name: "prompt", value: String(prompt.prefix(14000)))]
        parts.percentEncodedQuery = parts.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        return parts.url
    }
    static func latestReply(_ thread: Thread) -> String? {
        let root = home.appendingPathComponent("sessions")
        guard let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.contentModificationDateKey]) else { return nil }
        var matches: [URL] = []
        for case let file as URL in files where file.pathExtension == "jsonl" && file.lastPathComponent.contains(thread.id) { matches.append(file) }
        guard let file = matches.max(by: { ((try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast) < ((try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast) }) else { return nil }
        return SessionTranscripts.codexReply(in: file)
    }

    /// Named threads that are not archived, most recently updated first.
    static func all() -> [Thread] {
        guard let text = try? String(contentsOf: home.appendingPathComponent("session_index.jsonl"), encoding: .utf8) else { return [] }
        let archived = Set(((try? FileManager.default.contentsOfDirectory(atPath: home.appendingPathComponent("archived_sessions").path)) ?? [])
            .compactMap { name -> String? in name.hasSuffix(".jsonl") ? String(name.dropLast(6).suffix(36)) : nil })
        var latest: [String: Thread] = [:]
        for line in text.split(separator: "\n") {
            guard let d = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                  let id = d["id"] as? String, let title = d["thread_name"] as? String, !title.isEmpty, !archived.contains(id) else { continue }
            let updated = d["updated_at"] as? String ?? ""
            if let old = latest[id], old.updated >= updated { continue }
            latest[id] = Thread(id: id, title: title, updated: updated)
        }
        return latest.values.sorted { $0.updated > $1.updated }
    }

    /// "latest", an id (a prefix is enough) or words from the title, matched by stems as in
    /// ClaudeSessions.find, since Russian endings differ.
    static func find(_ query: String, in threads: [Thread]? = nil) -> Thread? {
        let threads = threads ?? all()
        let q = query.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if q.isEmpty || q == "latest" || q == "focused" { return threads.first }
        if q.count >= 6, let byID = threads.first(where: { $0.id.lowercased().hasPrefix(q) }) { return byID }
        if let whole = threads.first(where: { $0.title.lowercased().contains(q) }) { return whole }
        let stems = q.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).filter { $0.count >= 3 }
            .map { $0.count > 5 ? String($0.prefix($0.count - 2)) : String($0) }
        guard !stems.isEmpty else { return nil }
        var best: Thread?, bestScore = 0
        for thread in threads {
            let score = stems.filter { thread.title.lowercased().contains($0) }.count
            if score > bestScore { best = thread; bestScore = score }
        }
        return best
    }

    /// Put the thread on screen and wait until ChatGPT really shows it.
    static func open(_ thread: Thread) async throws {
        try Task.checkCancellation()
        guard let url = continuationURL(thread), NSWorkspace.shared.open(url) else {
            throw VoiceError.message("Could not open Codex thread “\(thread.title)”.")
        }
        for _ in 0..<50 {
            if titleOnScreen() == thread.title { DebugLog.write("CODEX: opened «\(thread.title)» by link"); return }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        throw VoiceError.message("Codex did not show thread “\(thread.title)”.")
    }

    /// A new Codex thread with the prompt already in its box (not sent).
    static func openNew(prompt: String) async throws {
        try Task.checkCancellation()
        guard let url = newThreadURL(prompt: prompt), NSWorkspace.shared.open(url) else { throw VoiceError.message("Could not open a new Codex thread.") }
        let probe = String(prompt.trimmingCharacters(in: .whitespacesAndNewlines).prefix(30))
        for _ in 0..<50 {
            if composerText()?.contains(probe) == true { DebugLog.write("CODEX: opened a new thread by link"); return }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        throw VoiceError.message("A new Codex thread opened, but its prompt could not be confirmed.")
    }

    /// Keyboard focus into the message box, so a paste lands there.
    static func focusComposer() async -> Bool {
        guard !Task.isCancelled else { return false }
        for _ in 0..<30 {
            guard !Task.isCancelled else { return false }
            guard let (root, box) = composer() else { try? await Task.sleep(nanoseconds: 100_000_000); continue }
            if let focused = AX.element(root, kAXFocusedUIElementAttribute), CFEqual(focused, box) { return true }
            AXUIElementSetAttributeValue(box, kAXFocusedAttribute as CFString, kCFBooleanTrue)
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        return false
    }

    /// The focused/main window is authoritative, not the first window in the list.
    private static func currentWindow(_ root: AXUIElement) -> AXUIElement? {
        AX.element(root, kAXFocusedWindowAttribute) ?? AX.element(root, kAXMainWindowAttribute)
    }

    /// The app's own page (app://…) in that window. The window also holds other web
    /// areas: a browser preview panel, and on 2026-09-27 a hidden page titled "ChatGPT"
    /// placed above the window that came first and made an open task look unopened.
    private static func appPage(_ root: AXUIElement) -> AXUIElement? {
        guard let window = currentWindow(root) else { return nil }
        var pages: [AXUIElement] = []
        func search(_ element: AXUIElement, _ depth: Int) {
            if AX.string(element, kAXRoleAttribute) == "AXWebArea" { pages.append(element); return }
            guard depth < 16 else { return }
            for child in AX.children(element) { search(child, depth + 1) }
        }
        search(window, 0)
        let bounds = AX.frame(window)?.insetBy(dx: -1, dy: -1)
        func inside(_ page: AXUIElement) -> Bool { bounds.map { frame in AX.frame(page).map { frame.contains($0) } ?? false } ?? false }
        func own(_ page: AXUIElement) -> Bool { (AX.value(page, kAXURLAttribute) as? URL)?.scheme == "app" }
        return pages.first { own($0) && inside($0) } ?? pages.first(where: own) ?? pages.first(where: inside) ?? pages.first
    }

    /// Title of the task in the window currently receiving input.
    static func titleOnScreen() -> String? {
        guard let root = appRoot(), let page = appPage(root) else { return nil }
        return AX.string(page, kAXTitleAttribute)
    }

    /// The draft in the message box. An empty box reports its placeholder as the
    /// value ("\nWork with ChatGPT", the same as its title): that is no draft.
    static func composerText() -> String? {
        guard let (_, box) = composer() else { return nil }
        let value = AX.string(box, kAXValueAttribute)
        let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let placeholders = [kAXPlaceholderValueAttribute, kAXTitleAttribute, kAXDescriptionAttribute]
            .map { AX.string(box, $0).trimmingCharacters(in: .whitespacesAndNewlines) }
        return !text.isEmpty && placeholders.contains(text) ? "" : value
    }

    /// A new user message in saved history, with its own timestamp checked.
    static func threadWithMessage(_ text: String, since: Date, expectedID: String? = nil) -> Thread? {
        let day = DateFormatter(); day.dateFormat = "yyyy/MM/dd"
        for date in [Date(), Date().addingTimeInterval(-86400)] {
            let folder = home.appendingPathComponent("sessions").appendingPathComponent(day.string(from: date))
            let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
            for file in files where (expectedID == nil || file.lastPathComponent.contains(expectedID!)) && ((try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast) >= since {
                guard SessionTranscripts.hasUserMessage(in: file, text: text, since: since, codex: true) else { continue }
                let id = String(file.deletingPathExtension().lastPathComponent.suffix(36))
                return all().first { $0.id == id } ?? Thread(id: id, title: "", updated: "")
            }
        }
        return nil
    }

    /// Saved history can lag while a running task queues new input. The exact
    /// message in the conversation and an empty composer prove UI delivery too.
    /// Editable fields are excluded, so a draft can never count as a receipt.
    static func messageOnScreen(_ text: String, title: String) -> Bool {
        guard !title.isEmpty, titleOnScreen() == title,
              composerText()?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true,
              let root = appRoot(), let page = appPage(root) else { return false }
        return SessionTranscripts.shownAsSent(text, in: page)
    }

    private static func appRoot() -> AXUIElement? {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first else { return nil }
        let root = AXUIElementCreateApplication(app.processIdentifier)
        MacController.exposeWebContent(app, root: root)   // ChatGPT is Electron: its content is hidden until asked for
        AXUIElementSetMessagingTimeout(root, 0.3)
        return root
    }
    /// The message box is the last text area on the app's page. Pages nested in it
    /// (a browser preview) are skipped: a text area there is not the composer.
    private static func composer() -> (AXUIElement, AXUIElement)? {
        guard let root = appRoot(), let page = appPage(root) else { return nil }
        var found: AXUIElement?
        func search(_ element: AXUIElement, _ depth: Int) {
            let role = AX.string(element, kAXRoleAttribute)
            if depth > 0 && role == "AXWebArea" { return }
            if role == kAXTextAreaRole { found = element }
            guard depth < 60 else { return }
            for child in AX.children(element) { search(child, depth + 1) }
        }
        search(page, 0)
        return found.map { (root, $0) }
    }
}
