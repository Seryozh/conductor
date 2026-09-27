import AppKit
import ApplicationServices

/// Arrange app windows on the selected display.
/// Each placement names an app, optionally part of a window title, and a rectangle in
/// fractions of the screen's visible area (menu bar and Dock excluded). Uses the
/// Accessibility permission Conductor already has; no new macOS permission is needed.
struct WindowPlacement {
    let app: String
    let title: String?
    let rect: [Double]   // x, y, width, height as fractions; y = 0 is the top
}

enum WindowArranger {
    static var aliases: [String: String] {
        ["chrome": "Google Chrome", "claude": "Claude", "finder": "Finder"]
            .merging(VoiceLocalization.aliases("apps.aliases")) { _, localized in localized }
    }

    /// Resolve a product name to a stable app identity even when its display name differs.
    static func bundleAlias(_ name: String) -> String? {
        let normalized = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let resolved = (aliases[normalized] ?? normalized).lowercased()
        return ["codex": "com.openai.codex", "chatgpt": "com.openai.codex", "claude": "com.anthropic.claudefordesktop", "google chrome": "com.google.Chrome"][resolved]
    }

    static func runningApp(_ name: String) -> NSRunningApplication? {
        let wanted = (aliases[name.lowercased()] ?? name).lowercased()
        let apps = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }
        if let bundle = bundleAlias(name), let exact = apps.first(where: { $0.bundleIdentifier?.lowercased() == bundle.lowercased() }) { return exact }
        return apps.first { $0.localizedName?.lowercased() == wanted }
            ?? apps.first { ($0.localizedName?.lowercased() ?? "").contains(wanted) }
            ?? apps.first { ($0.bundleIdentifier?.lowercased() ?? "").contains(wanted) }
    }

    static func window(of app: NSRunningApplication, title: String?) -> AXUIElement? {
        let root = AXUIElementCreateApplication(app.processIdentifier)
        let windows = (AX.value(root, kAXWindowsAttribute) as? [AXUIElement]) ?? []
        let standard = windows.filter { let sub = AX.string($0, kAXSubroleAttribute); return sub.isEmpty || sub == kAXStandardWindowSubrole }
        if let title, !title.isEmpty,
           let match = standard.first(where: { AX.string($0, kAXTitleAttribute).lowercased().contains(title.lowercased()) }) { return match }
        return AX.element(root, kAXMainWindowAttribute) ?? AX.element(root, kAXFocusedWindowAttribute) ?? standard.first
    }

    /// Screen for the layout: the one under the mouse, or a 1-based index.
    static func screen(_ index: Int?) -> NSScreen? {
        if let index, index >= 1, index <= NSScreen.screens.count { return NSScreen.screens[index - 1] }
        return NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main
    }

    /// Place every window and return its actual position and size.
    static func arrange(_ placements: [WindowPlacement], screenIndex: Int?) async throws -> [String] {
        guard let screen = screen(screenIndex), let primary = NSScreen.screens.first else { throw VoiceError.message("No display was found.") }
        let visible = screen.visibleFrame
        var report: [String] = []
        for placement in placements {
            guard placement.rect.count == 4 else { throw VoiceError.message("Invalid window rectangle for \(placement.app).") }
            guard let app = runningApp(placement.app) else { throw VoiceError.message("\(placement.app) is not running.") }
            guard let window = window(of: app, title: placement.title) else { throw VoiceError.message("No matching window was found for \(placement.app)\(placement.title.map { " (\($0))" } ?? "").") }
            let r = placement.rect.map { min(max($0, 0), 1) }
            // Visible frame is in bottom-left screen coordinates; Accessibility uses top-left of the primary screen.
            let width = (visible.width * r[2]).rounded(), height = (visible.height * r[3]).rounded()
            let left = (visible.minX + visible.width * r[0]).rounded()
            let top = (primary.frame.maxY - (visible.maxY - visible.height * r[1])).rounded()
            if AX.value(window, "AXFullScreen") as? Bool == true { AXUIElementSetAttributeValue(window, "AXFullScreen" as CFString, kCFBooleanFalse); try await Task.sleep(nanoseconds: 900_000_000) }
            AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
            // Chrome animates resizes while its enhanced accessibility mode is on.
            let root = AXUIElementCreateApplication(app.processIdentifier)
            let enhanced = AX.value(root, "AXEnhancedUserInterface") as? Bool == true
            if enhanced { AXUIElementSetAttributeValue(root, "AXEnhancedUserInterface" as CFString, kCFBooleanFalse) }
            var origin = CGPoint(x: left, y: top), size = CGSize(width: width, height: height)
            let position = AXValueCreate(.cgPoint, &origin)!, dimension = AXValueCreate(.cgSize, &size)!
            // Position, size, position again: some apps clamp a size that would cross the screen edge.
            AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, position)
            AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, dimension)
            AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, position)
            try await Task.sleep(nanoseconds: 250_000_000)
            AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, dimension)
            if enhanced { AXUIElementSetAttributeValue(root, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue) }
            AXUIElementPerformAction(window, kAXRaiseAction as CFString)
            let actual = AX.frame(window) ?? .zero
            let name = app.localizedName ?? placement.app
            let line = "\(name)\(placement.title.map { " (\($0))" } ?? ""): requested x=\(Int(left)) y=\(Int(top)) \(Int(width))×\(Int(height)), actual x=\(Int(actual.minX)) y=\(Int(actual.minY)) \(Int(actual.width))×\(Int(actual.height))"
            DebugLog.write("ARRANGE: " + line)
            report.append(line)
        }
        return report
    }
}
