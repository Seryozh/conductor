import AppKit
import ApplicationServices
import ImageIO
import UniformTypeIdentifiers

/// Named accessibility controls and point-scaled screenshots for local CLI clients.
enum ScreenTools {
    static let actionable: Set<String> = ["AXButton", "AXLink", "AXMenuItem", "AXMenuButton", "AXPopUpButton", "AXCheckBox",
        "AXRadioButton", "AXTab", "AXTextField", "AXTextArea", "AXComboBox", "AXSlider", "AXIncrementor", "AXDisclosureTriangle", "AXCell", "AXRow"]
    struct Control { let element: AXUIElement; let role: String; let name: String; let frame: CGRect? }

    static func app(named spoken: String) -> NSRunningApplication? {
        let running = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular || $0.activationPolicy == .accessory }
        let list = running.map { (name: $0.localizedName ?? "", bundle: $0.bundleIdentifier ?? "") }
        return OpenApps.matching(spoken, in: list).first.map { running[$0] }
    }

    /// Named controls in the app's windows, top to bottom.
    static func controls(_ app: NSRunningApplication) -> [Control] {
        let root = AXUIElementCreateApplication(app.processIdentifier)
        MacController.exposeWebContent(app, root: root)
        AXUIElementSetMessagingTimeout(root, 0.3)
        var found: [Control] = []
        func walk(_ element: AXUIElement, _ depth: Int) {
            guard depth < 70, found.count < 3000 else { return }
            let role = AX.string(element, kAXRoleAttribute)
            if actionable.contains(role) {
                var name = AX.label(element)
                if name.isEmpty, role == "AXRow" || role == "AXCell" {
                    name = AX.children(element).lazy.map { AX.label($0).isEmpty ? AX.string($0, kAXValueAttribute) : AX.label($0) }.first { !$0.isEmpty } ?? ""
                }
                let hidden = (AX.value(element, kAXHiddenAttribute) as? Bool) == true
                if !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !hidden {
                    found.append(Control(element: element, role: role, name: name.replacingOccurrences(of: "\n", with: " "), frame: AX.frame(element)))
                }
            }
            for child in AX.children(element) { walk(child, depth + 1) }
        }
        for window in (AX.value(root, kAXWindowsAttribute) as? [AXUIElement]) ?? [] { walk(window, 0) }
        return found
    }

    /// `Conductor --ui "App" [words]`: one line per named control with its center in screen points.
    static func list(appName: String, filter: String?) -> String {
        guard AXIsProcessTrusted() else { return "FAILED: Enable Conductor in macOS Accessibility to read controls." }
        guard let app = app(named: appName) else { return "FAILED: No running app matches «\(appName)». Open apps:\n" + OpenApps.summary() }
        let words = filter?.lowercased().split(separator: " ").map(String.init) ?? []
        let all = controls(app)
        let shown = all.filter { control in words.isEmpty || words.allSatisfy { control.name.lowercased().contains($0) } }
        let screen = NSScreen.screens.first?.frame.size ?? .zero
        var lines = ["\(OpenApps.name(app)): \(shown.count) of \(all.count) named controls; screen \(Int(screen.width))×\(Int(screen.height)) points. Press one with: Conductor --press \"\(OpenApps.name(app))\" \"name\""]
        for control in shown.prefix(250) {
            let place = control.frame.map { "\(Int($0.midX)),\(Int($0.midY))" } ?? "off-screen"
            let secure = AX.string(control.element, kAXSubroleAttribute) == kAXSecureTextFieldSubrole || (AX.value(control.element, "AXProtectedContent") as? Bool) == true
            let value = control.role == "AXTextArea" || control.role == "AXTextField" ? " = «" + (secure ? "[redacted]" : String(AX.string(control.element, kAXValueAttribute).prefix(80))) + "»" : ""
            lines.append("\(control.role.dropFirst(2)) «\(control.name.prefix(90))»\(value) @ \(place)")
        }
        if shown.count > 250 { lines.append("… \(shown.count - 250) more: add words to filter") }
        return lines.joined(separator: "\n")
    }

    /// `Conductor --press "App" "name" [n]`: brings the app forward and presses the control whose
    /// name matches (exact first, then containing); n picks among several matches (1-based).
    static func press(appName: String, name: String, pick: Int?) async -> String {
        guard !Task.isCancelled else { return "FAILED: The task was cancelled; no control was pressed." }
        guard AXIsProcessTrusted() else { return "FAILED: Enable Conductor in macOS Accessibility to press controls." }
        guard let app = app(named: appName) else { return "FAILED: no running app matches «\(appName)»." }
        let wanted = name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !wanted.isEmpty else { return "FAILED: Give a nonempty control name." }
        let all = controls(app)
        var matches = all.filter { $0.name.lowercased() == wanted }
        if matches.isEmpty { matches = all.filter { $0.name.lowercased().contains(wanted) } }
        guard !matches.isEmpty else { return "FAILED: no control named «\(name)» in \(OpenApps.name(app)). See: Conductor --ui \"\(OpenApps.name(app))\"" }
        if matches.count > 1, pick == nil {
            return "AMBIGUOUS: \(matches.count) controls match «\(name)»; add the number:\n" + matches.prefix(12).enumerated().map { "\($0.offset + 1). \($0.element.role.dropFirst(2)) «\($0.element.name.prefix(90))» @ " + ($0.element.frame.map { "\(Int($0.midX)),\(Int($0.midY))" } ?? "off-screen") }.joined(separator: "\n")
        }
        if let pick, !(1...matches.count).contains(pick) { return "FAILED: Match number must be between 1 and \(matches.count)." }
        let control = matches[(pick ?? 1) - 1]
        // Conductor's own floating windows take an AX press without focus; activating it would steal the
        // front app from whatever a running command is driving (the mouse painting, for one).
        if app.bundleIdentifier != Bundle.main.bundleIdentifier, NSWorkspace.shared.frontmostApplication?.processIdentifier != app.processIdentifier {
            guard !Task.isCancelled else { return "FAILED: The task was cancelled; no control was pressed." }
            app.activate()
            do {
                for _ in 0..<20 where NSWorkspace.shared.frontmostApplication?.processIdentifier != app.processIdentifier {
                    try Task.checkCancellation()
                    try await Task.sleep(nanoseconds: 50_000_000)
                }
                try await Task.sleep(nanoseconds: 250_000_000)
            } catch { return "FAILED: The task was cancelled; no control was pressed." }
            guard NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier else {
                return "FAILED: The requested app did not become frontmost; no control was pressed."
            }
        }
        guard !Task.isCancelled else { return "FAILED: The task was cancelled; no control was pressed." }
        let label = "\(control.role.dropFirst(2)) «\(control.name.prefix(90))»"
        if control.role == "AXTextArea" || control.role == "AXTextField" || control.role == "AXComboBox" {
            guard AXUIElementSetAttributeValue(control.element, kAXFocusedAttribute as CFString, kCFBooleanTrue) == .success else { return "FAILED: Could not focus \(label)." }
            return "focused \(label) in \(OpenApps.name(app))"
        }
        if AX.actions(control.element).contains(kAXPressAction), AXUIElementPerformAction(control.element, kAXPressAction as CFString) == .success {
            return "pressed \(label) in \(OpenApps.name(app))"
        }
        guard let frame = control.frame else { return "FAILED: \(label) cannot be pressed and has no place on screen." }
        guard click(at: CGPoint(x: frame.midX, y: frame.midY)) else { return "FAILED: Could not create pointer events." }
        return "clicked \(label) at \(Int(frame.midX)),\(Int(frame.midY)) in \(OpenApps.name(app))"
    }

    @discardableResult static func click(at point: CGPoint) -> Bool {
        guard !Task.isCancelled else { return false }
        guard let down = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: point, mouseButton: .left),
              let up = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: point, mouseButton: .left) else { return false }
        down.post(tap: .cghidEventTap); usleep(40_000); up.post(tap: .cghidEventTap)
        return true
    }

    /// `Conductor --look [file] [--no-grid]`: the main screen with one pixel per screen point and a
    /// labelled 100-point grid, so a click position is read off the picture instead of guessed.
    static func look(to path: String, grid: Bool) -> String {
        let raw = FileManager.default.temporaryDirectory.appendingPathComponent("conductor-look-raw-\(getpid()).png")
        defer { try? FileManager.default.removeItem(at: raw) }
        let shot = Process(); shot.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture"); shot.arguments = ["-x", "-m", raw.path]
        guard (try? shot.run()) != nil else { return "FAILED: screencapture did not start." }
        shot.waitUntilExit()
        guard let source = CGImageSourceCreateWithURL(raw as CFURL, nil), let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            return "FAILED: no screenshot (Screen Recording permission for Conductor?)."
        }
        let size = NSScreen.screens.first?.frame.size ?? CGSize(width: image.width, height: image.height)
        return render(image, to: path, size: size, grid: grid)
    }

    /// Captures only one verified window belonging to the requested running app.
    /// It never falls back to the desktop if lookup or capture fails.
    static func lookApp(appName: String, to path: String) -> String {
        guard let app = app(named: appName) else { return "FAILED: No running app matches «\(appName)»." }
        guard CGPreflightScreenCaptureAccess() else { return "FAILED: Screen Recording permission is required to capture this app's window." }
        let windows = (CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]) ?? []
        let candidates: [(id: CGWindowID, bounds: CGRect)] = windows.compactMap { info in
            guard (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == app.processIdentifier,
                  let number = info[kCGWindowNumber as String] as? NSNumber,
                  let rect = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: rect), bounds.width > 1, bounds.height > 1,
                  (info[kCGWindowAlpha as String] as? Double ?? 1) > 0 else { return nil }
            return (number.uint32Value, bounds)
        }
        guard let chosen = candidates.max(by: { $0.bounds.width * $0.bounds.height < $1.bounds.width * $1.bounds.height }) else {
            return "FAILED: No visible window belongs to «\(OpenApps.name(app))»."
        }
        let raw = FileManager.default.temporaryDirectory.appendingPathComponent("conductor-window-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: raw) }
        let shot = Process(); shot.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        shot.arguments = ["-x", "-o", "-l", String(chosen.id), raw.path]
        guard (try? shot.run()) != nil else { return "FAILED: Window capture could not start." }
        shot.waitUntilExit()
        guard shot.terminationStatus == 0,
              let source = CGImageSourceCreateWithURL(raw as CFURL, nil), let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            return "FAILED: Could not capture the selected app window. No desktop capture was taken."
        }
        let result = render(image, to: path, size: chosen.bounds.size, grid: false)
        if result.hasPrefix("FAILED") { return result }
        return result + " App: \(OpenApps.name(app)) (\(app.bundleIdentifier ?? "unknown bundle")), pid \(app.processIdentifier), window \(chosen.id); screen bounds \(Int(chosen.bounds.minX)),\(Int(chosen.bounds.minY)),\(Int(chosen.bounds.width)),\(Int(chosen.bounds.height)) points. Image coordinates start at this window's top-left."
    }

    /// Image bytes for a result check of one app. The supplied PID and optional
    /// Accessibility window frame determine scope; failure never captures a display.
    static func captureApp(app: NSRunningApplication, preferredWindowFrame: CGRect? = nil, maxWidth: Int = 1280) -> Data? {
        guard !Task.isCancelled, !app.isTerminated, maxWidth > 0, CGPreflightScreenCaptureAccess() else { return nil }
        let windows = (CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]) ?? []
        guard let chosen = captureWindow(in: windows, ownerPID: app.processIdentifier, preferredFrame: preferredWindowFrame) else { return nil }
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("conductor-check-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: file) }
        guard !Task.isCancelled else { return nil }
        let shot = Process(); shot.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        shot.arguments = ["-x", "-o", "-l", String(chosen.id), file.path]
        guard (try? shot.run()) != nil else { return nil }
        shot.waitUntilExit()
        guard !Task.isCancelled, shot.terminationStatus == 0,
              let source = CGImageSourceCreateWithURL(file as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        let width = min(image.width, maxWidth)
        let height = max(1, Int((Double(image.height) * Double(width) / Double(image.width)).rounded()))
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let resized = context.makeImage() else { return nil }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, resized, [kCGImageDestinationLossyCompressionQuality: 0.7] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }

    /// Pure selection helper, also tested without reading the desktop.
    static func captureWindow(in windows: [[String: Any]], ownerPID: Int32, preferredFrame: CGRect?) -> (id: CGWindowID, bounds: CGRect)? {
        let candidates: [(id: CGWindowID, bounds: CGRect)] = windows.compactMap { info in
            guard (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == ownerPID,
                  let number = info[kCGWindowNumber as String] as? NSNumber,
                  let rect = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: rect), bounds.width > 1, bounds.height > 1,
                  (info[kCGWindowAlpha as String] as? Double ?? 1) > 0,
                  (info[kCGWindowLayer as String] as? Int ?? 0) == 0 else { return nil }
            return (number.uint32Value, bounds)
        }
        if let preferredFrame {
            // Both APIs describe bounds in screen points; allow rounding differences.
            return candidates.first {
                abs($0.bounds.minX - preferredFrame.minX) <= 3 && abs($0.bounds.minY - preferredFrame.minY) <= 3
                    && abs($0.bounds.width - preferredFrame.width) <= 3 && abs($0.bounds.height - preferredFrame.height) <= 3
            }
        }
        return candidates.max { $0.bounds.width * $0.bounds.height < $1.bounds.width * $1.bounds.height }
    }

    private static func render(_ image: CGImage, to path: String, size: CGSize, grid: Bool) -> String {
        let width = Int(size.width), height = Int(size.height)
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return "FAILED: no drawing context." }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        if grid {
            // Core Graphics counts y from the bottom; the labels show screen points from the top.
            let graphics = NSGraphicsContext(cgContext: context, flipped: false)
            NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = graphics
            let font = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .bold)
            let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.white, .backgroundColor: NSColor(calibratedRed: 0.85, green: 0, blue: 0.3, alpha: 0.85)]
            context.setLineWidth(1)
            for x in stride(from: 100, to: width, by: 100) {
                context.setStrokeColor(NSColor(calibratedRed: 1, green: 0, blue: 0.4, alpha: x % 500 == 0 ? 0.55 : 0.28).cgColor)
                context.stroke(CGRect(x: CGFloat(x), y: 0, width: 0, height: CGFloat(height)))
                NSAttributedString(string: "\(x)", attributes: attributes).draw(at: CGPoint(x: CGFloat(x) + 2, y: CGFloat(height) - 13))
                NSAttributedString(string: "\(x)", attributes: attributes).draw(at: CGPoint(x: CGFloat(x) + 2, y: 2))
            }
            for y in stride(from: 100, to: height, by: 100) {
                context.setStrokeColor(NSColor(calibratedRed: 1, green: 0, blue: 0.4, alpha: y % 500 == 0 ? 0.55 : 0.28).cgColor)
                let flipped = CGFloat(height - y)
                context.stroke(CGRect(x: 0, y: flipped, width: CGFloat(width), height: 0))
                NSAttributedString(string: "\(y)", attributes: attributes).draw(at: CGPoint(x: 2, y: flipped + 2))
                NSAttributedString(string: "\(y)", attributes: attributes).draw(at: CGPoint(x: CGFloat(width) - 26, y: flipped + 2))
            }
            NSGraphicsContext.restoreGraphicsState()
        }
        guard let result = context.makeImage(), let destination = CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL, UTType.png.identifier as CFString, 1, nil) else { return "FAILED: could not write \(path)." }
        CGImageDestinationAddImage(destination, result, nil)
        guard CGImageDestinationFinalize(destination) else { return "FAILED: could not write \(path)." }
        return "\(path): \(width)×\(height), one pixel = one point (0,0 image top-left)" + (grid ? "; grid lines every 100 points, labelled in points." : ".")
    }
}
