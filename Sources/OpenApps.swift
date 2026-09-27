import AppKit
import ApplicationServices

/// Open-app context and graceful quit actions available to the reasoning brain.
/// Every brain message carries `summary()`; the brain's "quit" and "quit_except" fields run `close`.
enum OpenApps {
    /// Dock apps, front first, each with its window titles; then the menu-bar apps.
    static func summary() -> String {
        let running = NSWorkspace.shared.runningApplications
        let front = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let dock = running.filter { $0.activationPolicy == .regular && !$0.isTerminated }
            .sorted { ($0.processIdentifier == front ? 0 : 1) < ($1.processIdentifier == front ? 0 : 1) }
        let lines = dock.map { app -> String in
            var notes: [String] = []
            if app.processIdentifier == front { notes.append("front") }
            if app.isHidden { notes.append("hidden") }
            let titles = windowTitles(app)
            return "- " + name(app) + (notes.isEmpty ? "" : " (" + notes.joined(separator: ", ") + ")")
                + (titles.isEmpty ? "" : ": " + titles.joined(separator: ", "))
        }
        let menuBar = running.filter { $0.activationPolicy == .accessory && !($0.bundleIdentifier ?? "").hasPrefix("com.apple.") }.compactMap(\.localizedName)
        return "Open apps (Dock), front first:\n" + lines.joined(separator: "\n")
            + (menuBar.isEmpty ? "" : "\nMenu-bar apps: " + menuBar.joined(separator: ", "))
    }

    /// Window titles; each app gets a quarter second, so a hung app cannot stall a command.
    static func windowTitles(_ app: NSRunningApplication, limit: Int = 8) -> [String] {
        let root = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(root, 0.25)
        let windows = (AX.value(root, kAXWindowsAttribute) as? [AXUIElement]) ?? []
        let titles = windows.prefix(limit).compactMap { window -> String? in
            AXUIElementSetMessagingTimeout(window, 0.25)
            let title = AX.string(window, kAXTitleAttribute).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { return nil }
            let short = title.count > 60 ? String(title.prefix(60)) + "…" : title
            return "«\(short)»" + (AX.value(window, kAXMinimizedAttribute) as? Bool == true ? " minimized" : "")
        }
        return titles + (windows.count > limit ? ["+\(windows.count - limit) more"] : [])
    }

    static func name(_ app: NSRunningApplication) -> String { app.localizedName ?? app.bundleIdentifier ?? "pid \(app.processIdentifier)" }

    /// Match an exact app name, bundle id, localized alias, or unambiguous partial name.
    static func matching(_ spoken: String, in apps: [(name: String, bundle: String)]) -> [Int] {
        let raw = spoken.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let wanted = (WindowArranger.aliases[raw] ?? raw).lowercased()
        guard !wanted.isEmpty else { return [] }
        let bundleAlias = WindowArranger.bundleAlias(spoken)?.lowercased()
        let exact = apps.indices.filter { apps[$0].name.lowercased() == wanted || apps[$0].bundle.lowercased() == wanted || apps[$0].bundle.lowercased() == bundleAlias }
        if !exact.isEmpty { return exact }
        let partial = apps.indices.filter { apps[$0].name.lowercased().contains(wanted) }
        return Set(partial.map { apps[$0].name }).count == 1 ? partial : []
    }

    /// Whether a keep-list entry matches this app.
    static func keeps(_ spoken: String, name: String, bundle: String) -> Bool {
        let raw = spoken.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let wanted = (WindowArranger.aliases[raw] ?? raw).lowercased()
        let app = name.lowercased()
        guard !wanted.isEmpty else { return false }
        return app == wanted || bundle.lowercased() == wanted || bundle.lowercased() == WindowArranger.bundleAlias(spoken)?.lowercased() || app.contains(wanted) || wanted.contains(app)
    }

    struct Outcome {
        var closed: [String] = [], stillOpen: [String] = [], notFound: [String] = []
        /// A concise user-facing summary.
        var text: String {
            var parts: [String] = []
            if !closed.isEmpty { parts.append("Closed: " + closed.joined(separator: ", ") + ".") }
            if !stillOpen.isEmpty { parts.append("Still open after eight seconds: " + stillOpen.joined(separator: ", ") + " (the app may be slow to close or may be asking to save work).") }
            if !notFound.isEmpty { parts.append("Not found among open apps: " + notFound.joined(separator: ", ") + ".") }
            return parts.isEmpty ? "No apps needed to close." : parts.joined(separator: " ")
        }
    }

    /// Close apps politely, as Command+Q does: an app with unsaved work asks and stays open.
    /// `names` are closed; with `keep`, every other Dock app closes too. Waits up to 8 seconds
    /// and reports what really closed.
    static func close(_ names: [String], keep: [String]?) async -> Outcome {
        let apps = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular && !$0.isTerminated }
        let labels = apps.map { (name: name($0), bundle: $0.bundleIdentifier ?? "") }
        var outcome = Outcome()
        var chosen: [Int] = []
        for spoken in names {
            let found = matching(spoken, in: labels)
            if found.isEmpty { outcome.notFound.append(spoken) } else { chosen += found }
        }
        if let keep {
            chosen += apps.indices.filter { index in !keep.contains { keeps($0, name: labels[index].name, bundle: labels[index].bundle) } }
        }
        var seen = Set<pid_t>()
        let targets = chosen.map { apps[$0] }.filter { seen.insert($0.processIdentifier).inserted }
        for app in targets { app.terminate() }
        func alive(_ app: NSRunningApplication) -> Bool { kill(app.processIdentifier, 0) == 0 }
        for _ in 0..<40 where targets.contains(where: alive) { try? await Task.sleep(nanoseconds: 200_000_000) }
        outcome.closed = targets.filter { !alive($0) }.map(name)
        outcome.stillOpen = targets.filter(alive).map(name)
        DebugLog.write("QUIT: closed [\(outcome.closed.joined(separator: ", "))] still open [\(outcome.stillOpen.joined(separator: ", "))] not found [\(outcome.notFound.joined(separator: ", "))]" + (keep.map { " keep [\($0.joined(separator: ", "))]" } ?? ""))
        return outcome
    }
}
