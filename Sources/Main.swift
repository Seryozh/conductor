import AppKit
import UniformTypeIdentifiers
import SwiftUI
import Darwin

/// Allows editing without activating Jev over the app being controlled.
final class CommandBarPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSMenuDelegate {
    let model = AppModel()
    var window: NSWindow!
    var overlay: NSPanel!
    var practice: NSWindow?
    var statusItem: NSStatusItem!
    var localControl: LocalControlServer?
    var hotkey: GlobalHotKey!
    var holdToTalk: HoldToTalkMonitor!
    var barHidden = false
    var pointerGeneration = 0
    let surfaceLimits = CommandSurfaceLimits()
    var requestedSurfaceSize = NSSize(width: CommandBarView.width, height: CommandBarView.railHeight)
    var commandAnchor: NSPoint?
    var resizingSurface = false
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let control = LocalControlServer()
        do {
            try control.start(runtime: { [weak self] in self?.model.localRuntimeStatus ?? [:] }, submit: { [weak self] command in
                self?.model.submitLocalCommand(command) ?? LocalCommandSubmission(state: "rejected", error: "The app is shutting down.")
            })
            localControl = control
            model.localCommandFinished = { [weak control] outcome, error in control?.finish(outcome: outcome, error: error) }
        } catch { DebugLog.write("LOCAL CONTROL: " + error.localizedDescription) }
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 840, height: 680), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = NSLocalizedString("Conductor Settings", comment: "Settings window title")
        window.minSize = NSSize(width: 760, height: 620)
        window.titlebarAppearsTransparent = true
        window.backgroundColor = NSColor(Palette.background)
        window.contentView = NSHostingView(rootView: SettingsView(model: model))
        window.isReleasedWhenClosed = false
        window.center()
        overlay = CommandBarPanel(contentRect: NSRect(x: 0, y: 0, width: CommandBarView.width, height: CommandBarView.railHeight), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        overlay.title = NSLocalizedString("Conductor command bar", comment: "Command bar window title")
        overlay.isOpaque = false; overlay.backgroundColor = .clear; overlay.hasShadow = true
        overlay.level = .floating; overlay.hidesOnDeactivate = false
        overlay.isFloatingPanel = true; overlay.becomesKeyOnlyIfNeeded = true
        overlay.isMovableByWindowBackground = true
        overlay.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        overlay.tabbingMode = .disallowed
        overlay.delegate = self
        overlay.contentView = NSHostingView(rootView: CommandBarView(model: model,
            openSettings: { [weak self] in self?.showSettings() },
            releaseKeyboard: { [weak self] in self?.releaseBarKeyboard() },
            resize: { [weak self] size in self?.resizeCommandSurface(to: size) }, limits: surfaceLimits))
        model.showAnswer = { [weak self] in self?.presentAnswer() }
        model.hideAnswer = { [weak self] in
            guard let self else { return }
            if self.barHidden { self.overlay.orderOut(nil) }
        }
        model.showOverlay = { [weak self] in self?.presentOverlay() }
        model.hideOverlay = {} // Pausing the microphone keeps the command bar available.
        model.beforeRequest = { [weak self] in self?.releaseBarKeyboard() }
        model.controller.onPrepareInput = { [weak self] in self?.releaseBarKeyboard() }
        model.controller.onPointerInput = { [weak self] active in
            guard let self else { return }
            self.pointerGeneration += 1
            let generation = self.pointerGeneration
            if active { self.overlay.ignoresMouseEvents = true }
            else {
                // Keep synthetic pointer events from hitting the floating bar.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
                    guard let self, generation == self.pointerGeneration else { return }
                    self.overlay.ignoresMouseEvents = false
                }
            }
        }
        model.showMain = { [weak self] in self?.showSettings() }
        model.showCommandBar = { [weak self] in self?.showCommandCenter() }
        for name in [NSWorkspace.didActivateApplicationNotification, NSWorkspace.activeSpaceDidChangeNotification] {
            NSWorkspace.shared.notificationCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in guard self?.barHidden == false else { return }; self?.presentOverlay() }
            }
        }
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in guard self?.barHidden == false else { return }; self?.presentOverlay() }
        }
        model.openPractice = { [weak self] in self?.showPractice() }
        model.focusPractice = { [weak self] in self?.practice?.makeKeyAndOrderFront(nil) }
        hotkey = GlobalHotKey()
        hotkey.onPress = { [weak self] in self?.model.toggleListening() }
        model.hotkeyWorking = hotkey.registered
        holdToTalk = HoldToTalkMonitor()
        holdToTalk.onDown = { [weak self] in self?.model.pushToTalkDown() }
        holdToTalk.onUp = { [weak self] in self?.model.pushToTalkUp() }
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "waveform", accessibilityDescription: NSLocalizedString("Conductor", comment: "Menu bar icon"))
        let menu = NSMenu()
        menu.delegate = self   // rebuilt on every open, so the checkmarks are current
        statusItem.menu = menu
        let mainMenu = NSMenu()
        let appMenu = NSMenu(); let appItem = NSMenuItem(); appItem.submenu = appMenu
        appMenu.addItem(withTitle: NSLocalizedString("Quit Conductor", comment: "Quit menu item"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        mainMenu.addItem(appItem)
        let edit = NSMenu(title: NSLocalizedString("Edit", comment: "Edit menu"))
        for (title, selector, key) in [("Undo", Selector(("undo:")), "z"), ("Cut", #selector(NSText.cut(_:)), "x"), ("Copy", #selector(NSText.copy(_:)), "c"), ("Paste", #selector(NSText.paste(_:)), "v"), ("Select All", #selector(NSText.selectAll(_:)), "a")] { edit.addItem(withTitle: NSLocalizedString(title, comment: "Edit menu item"), action: selector, keyEquivalent: key) }
        let editItem = NSMenuItem(); editItem.submenu = edit; mainMenu.addItem(editItem); NSApp.mainMenu = mainMenu
        if model.keyConfigured && model.microphoneGranted && model.speechGranted && model.accessibilityGranted {
            if !CommandLine.arguments.contains("--diagnostics") { model.toggleListening() }
        } else { model.showSetup = true; showWindow() }
        if CommandLine.arguments.contains("--diagnostics") { model.showSetup = true; showWindow() }
        presentOverlay()
        Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.statusItem.button?.image = NSImage(systemSymbolName: self.model.voiceState.icon, accessibilityDescription: NSLocalizedString("Conductor", comment: "Menu bar icon") + ": " + self.model.voiceState.rawValue)
                self.statusItem.button?.toolTip = "Conductor · " + self.model.phase + " · " + self.model.detail
            }
        }
    }
    /// Menu bar controls for the command bar, brain, and listening preferences.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        func add(_ title: String, _ selector: Selector?, key: String = "", state: Bool? = nil, id: String? = nil, indent: Bool = false) {
            let item = NSMenuItem(title: NSLocalizedString(title, comment: "Menu bar item"), action: selector, keyEquivalent: key)
            item.target = self; item.representedObject = id; item.isEnabled = selector != nil
            if let state { item.state = state ? .on : .off }
            if indent { item.indentationLevel = 1 }
            menu.addItem(item)
        }
        add("Show command bar", #selector(showCommandCenter))
        add("Settings…", #selector(showSettings), key: ",")
        if model.agentDashboardAvailable { add("Agent dashboard", #selector(openAgentDashboard)) }
        menu.addItem(.separator())
        add("Brain", nil)
        for choice in BrainChoice.all {
            let blocked = choice.codex && CodexBrain.binary() == nil
            add(choice.name + "  ·  " + (blocked ? "Codex CLI not found" : choice.short), blocked ? nil : #selector(pickBrain(_:)), state: model.brainModel == choice.id, id: choice.id, indent: true)
        }
        add("Start new conversation", #selector(resetConversation))
        add("Check a recording…", #selector(checkRecording))
        add("Run commands from a recording…", #selector(runRecording))
        menu.addItem(.separator())
        add("Speak answers", #selector(toggleVoiceAnswers), state: model.voiceFeedback)
        add("Continuous listening", #selector(toggleContinuous), state: model.continuousListening)
        add("Listen for one command (⌥ Space), or hold Fn", #selector(listen))
        menu.addItem(.separator())
        add("Hide command bar", #selector(hideCommandBar))
        add("Quit Conductor", #selector(quit), key: "q")
    }
    @objc func pickBrain(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String, let choice = BrainChoice.find(id) else { return }
        model.selectBrain(choice, by: "menu")
    }
    @objc func openAgentDashboard() { model.openAgentMap() }
    @objc func checkRecording() { chooseRecording(execute: false) }
    @objc func runRecording() { chooseRecording(execute: true) }
    private func chooseRecording(execute: Bool) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false; panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.audio]
        panel.prompt = NSLocalizedString(execute ? "Run commands" : "Check speech", comment: "Recording picker action")
        if panel.runModal() == .OK, let source = panel.url { model.replayRecording(source, execute: execute) }
    }
    @objc func resetConversation() { model.newConversation() }
    @objc func toggleVoiceAnswers() { model.voiceFeedback.toggle() }
    @objc func toggleContinuous() { model.continuousListening.toggle() }
    @objc func showWindow() { window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true) }
    @objc func showCommandCenter() {
        window.orderOut(nil)
        barHidden = false; presentOverlay()
    }
    @objc func hideCommandBar() { barHidden = true; overlay.orderOut(nil) }
    func releaseBarKeyboard() {
        guard overlay.isKeyWindow else { return }
        overlay.endEditing(for: nil); overlay.makeFirstResponder(nil); overlay.resignKey()
        if !model.practiceActive, let target = model.lastExternalApp, !target.isTerminated {
            NSApp.yieldActivation(to: target)
            target.activate(options: [.activateAllWindows])
        }
    }
    @objc func showSettings() { model.showSetup = true; showWindow() }
    @objc func listen() { model.toggleListening() }
    @objc func quit() { model.cancel(); LocalWhisper.shared.stop(); NSApp.terminate(nil) }
    @objc func showPractice() {
        if practice == nil {
            let view = PracticeView(model: model)
            practice = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 535, height: 465), styleMask: [.titled, .closable], backing: .buffered, defer: false)
            practice?.title = NSLocalizedString("Conductor · Practice", comment: "Practice window title")
            practice?.contentView = NSHostingView(rootView: view)
            practice?.isReleasedWhenClosed = false; practice?.delegate = self; practice?.center()
        }
        model.practiceActive = true; model.currentApp = "Practice window"
        practice?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }
    func windowWillClose(_ notification: Notification) {
        if (notification.object as? NSWindow) == practice { model.practiceActive = false }
    }
    func presentAnswer() {
        guard !model.answerText.isEmpty else { return }
        // A response uses the same nonactivating surface. It can still be shown after
        // the user hides the idle bar, matching the previous answer-window callback.
        if commandAnchor == nil { positionCommandSurface() }
        overlay.orderFrontRegardless()
    }
    func resizeCommandSurface(to size: NSSize) {
        requestedSurfaceSize = size
        positionCommandSurface()
    }
    private func positionCommandSurface() {
        guard let overlay else { return }
        let pointerScreen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }
        let screen = commandAnchor == nil ? (pointerScreen ?? NSScreen.main) : (overlay.screen ?? pointerScreen ?? NSScreen.main)
        guard let screen else { return }
        let visible = screen.visibleFrame
        let availableWidth = max(240, min(600, visible.width - 16))
        let availableHeight = max(CommandBarView.railHeight, min(520, visible.height - 16))
        if surfaceLimits.width != availableWidth { surfaceLimits.width = availableWidth }
        if surfaceLimits.height != availableHeight { surfaceLimits.height = availableHeight }
        if commandAnchor == nil { commandAnchor = NSPoint(x: visible.midX, y: visible.minY + 24) }
        let frame = CommandPanelGeometry.frame(size: requestedSurfaceSize, anchor: commandAnchor!, visibleFrame: visible)
        guard !NSEqualRects(frame, overlay.frame) else { return }
        resizingSurface = true
        overlay.setFrame(frame, display: true)
        resizingSurface = false
    }
    func windowDidMove(_ notification: Notification) {
        guard let moved = notification.object as? NSWindow, moved === overlay, !resizingSurface else { return }
        commandAnchor = NSPoint(x: moved.frame.midX, y: moved.frame.minY)
    }
    func windowDidChangeScreen(_ notification: Notification) {
        guard let moved = notification.object as? NSWindow, moved === overlay, !resizingSurface else { return }
        positionCommandSurface()
    }
    func presentOverlay() {
        guard !barHidden, let overlay else { return }
        positionCommandSurface()
        overlay.orderFrontRegardless()
    }
    func applicationWillTerminate(_ notification: Notification) { localControl?.stop() }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { showCommandCenter(); return false }
}

@main struct ConductorApp {
    @MainActor static func main() {
        let arguments = CommandLine.arguments
        func printUsage() {
            print("""
            Conductor
              Launch the app: Conductor [--diagnostics]
              Inspect it:     Conductor --status | --ui | --look | --look-app
              Control it:     Conductor --command | --press | --store-key
              Test it:        Conductor --self-test | --activity-test | --whisper-test
            """)
        }
        if arguments.contains("--store-key") { exit(LocalControlCLI.storeKey()) }
        if let flag = arguments.firstIndex(of: "--status") {
            let id = arguments.count > flag + 1 && !arguments[flag + 1].hasPrefix("--") ? arguments[flag + 1] : nil
            let (result, code) = LocalControlCLI.status(id: id); LocalControlCLI.printJSON(result); exit(code)
        }
        if let flag = arguments.firstIndex(of: "--command") {
            guard arguments.count > flag + 1 else { LocalControlCLI.printJSON(["state": "rejected", "error": "Usage: --command \"text\" [--id UUID] [--wait seconds]"]); exit(2) }
            func value(_ name: String) -> String? { guard let n = arguments.firstIndex(of: name), arguments.count > n + 1 else { return nil }; return arguments[n + 1] }
            let wait = value("--wait").flatMap(Double.init) ?? 0
            guard wait.isFinite, wait >= 0, wait <= 86400 else { LocalControlCLI.printJSON(["state": "rejected", "error": "Wait must be between 0 and 86400 seconds."]); exit(2) }
            let (result, code) = LocalControlCLI.command(arguments[flag + 1], id: value("--id") ?? UUID().uuidString, wait: wait)
            LocalControlCLI.printJSON(result); exit(code)
        }
        if let flag = arguments.firstIndex(of: "--ui") {
            guard arguments.count > flag + 1 else { print("Usage: --ui <app name or bundle ID> [filter]"); exit(2) }
            _ = NSApplication.shared
            let result = ScreenTools.list(appName: arguments[flag + 1], filter: arguments.count > flag + 2 ? arguments[(flag + 2)...].joined(separator: " ") : nil)
            print(result); exit(result.hasPrefix("FAILED") ? 1 : 0)
        }
        if let flag = arguments.firstIndex(of: "--press") {
            guard arguments.count > flag + 2 else { print("Usage: --press <app name or bundle ID> <control name> [match number]"); exit(2) }
            _ = NSApplication.shared
            let pick = arguments.count > flag + 3 ? Int(arguments[flag + 3]) : nil
            if arguments.count > flag + 3 && pick == nil { print("FAILED: Match number must be an integer."); exit(2) }
            Task { let result = await ScreenTools.press(appName: arguments[flag + 1], name: arguments[flag + 2], pick: pick); print(result); exit(result.hasPrefix("FAILED") || result.hasPrefix("AMBIGUOUS") ? 1 : 0) }
            RunLoop.main.add(Timer(timeInterval: 60, repeats: true) { _ in }, forMode: .default); CFRunLoopRun(); return
        }
        if let flag = arguments.firstIndex(of: "--look-app") {
            guard arguments.count > flag + 1 else { print("Usage: --look-app <app name or bundle ID> [file]"); exit(2) }
            _ = NSApplication.shared
            let path = arguments.count > flag + 2 ? arguments[flag + 2] : FileManager.default.temporaryDirectory.appendingPathComponent("conductor-window.png").path
            let result = ScreenTools.lookApp(appName: arguments[flag + 1], to: path); print(result); exit(result.hasPrefix("FAILED") ? 1 : 0)
        }
        if let flag = arguments.firstIndex(of: "--look") {
            _ = NSApplication.shared
            let path = arguments.count > flag + 1 && !arguments[flag + 1].hasPrefix("--") ? arguments[flag + 1] : FileManager.default.temporaryDirectory.appendingPathComponent("conductor-look.png").path
            let result = ScreenTools.look(to: path, grid: !arguments.contains("--no-grid")); print(result); exit(result.hasPrefix("FAILED") ? 1 : 0)
        }
        if let flag = CommandLine.arguments.firstIndex(of: "--speech-file-test"), CommandLine.arguments.count > flag + 1 {
            _ = NSApplication.shared
            NSApp.setActivationPolicy(.accessory)
            Task { @MainActor in
                do {
                    let transcript = try await SpeechFixtureTest().transcribe(URL(fileURLWithPath: CommandLine.arguments[flag + 1]))
                    var buffer = UtteranceBuffer(); buffer.update(transcript, at: 0)
                    let steps = [buffer.command]
                    let passed = CommandLine.arguments.contains("--transcribe-only") || ["chrome", "youtube", "search", "piano", "first video"].allSatisfy { transcript.lowercased().contains($0) } && buffer.explicitEnd && steps.count == 1
                    let report: [String: Any] = ["transcript": transcript, "command": buffer.command, "passed": passed, "on_device": true, "explicit_endpoint": buffer.explicitEnd, "steps": steps]
                    let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
                    if let reportFlag = CommandLine.arguments.firstIndex(of: "--report"), CommandLine.arguments.count > reportFlag + 1 { try data.write(to: URL(fileURLWithPath: CommandLine.arguments[reportFlag + 1])) }
                    print(String(data: data, encoding: .utf8)!)
                    exit(passed ? 0 : 1)
                } catch {
                    if let reportFlag = CommandLine.arguments.firstIndex(of: "--report"), CommandLine.arguments.count > reportFlag + 1,
                       let data = try? JSONSerialization.data(withJSONObject: ["passed": false, "error": error.localizedDescription]) {
                        try? data.write(to: URL(fileURLWithPath: CommandLine.arguments[reportFlag + 1]))
                    }
                    print("FAIL: \(error.localizedDescription)"); exit(1)
                }
            }
            NSApplication.shared.run(); return
        }
        if CommandLine.arguments.contains("--self-test") { SelfTests.run(); exit(0) }
        // What the brain sees of the open apps, and the real closing path, without the voice queue.
        if CommandLine.arguments.contains("--open-apps") { print(OpenApps.summary()); exit(0) }
        // Whisper through the app's own code path: --whisper-test file.wav (16 kHz mono 16-bit).
        if let flag = CommandLine.arguments.firstIndex(of: "--whisper-test"), CommandLine.arguments.count > flag + 1,
           let wav = FileManager.default.contents(atPath: CommandLine.arguments[flag + 1]), wav.count > 44 {
            guard LocalWhisper.shared.enabled && LocalWhisper.shared.installed else {
                print("Whisper is off or its server and model paths are not set in Settings."); exit(1)
            }
            LocalWhisper.shared.start()
            Task {
                guard await LocalWhisper.shared.waitUntilReady(timeout: 30) else {
                    LocalWhisper.shared.stop(); print("Whisper server did not start."); exit(1)
                }
                let result = await LocalWhisper.shared.transcribe(wav.subdata(in: 44..<wav.count), language: "ru")
                LocalWhisper.shared.stop()
                print(result ?? "NO ANSWER"); exit(result == nil ? 1 : 0)
            }
            RunLoop.main.add(Timer(timeInterval: 60, repeats: true) { _ in }, forMode: .default); CFRunLoopRun(); return
        }
        if let flag = CommandLine.arguments.firstIndex(where: { $0 == "--close-apps" || $0 == "--close-apps-except" }), CommandLine.arguments.count > flag + 1 {
            let names = CommandLine.arguments[flag + 1].split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            let except = CommandLine.arguments[flag] == "--close-apps-except"
            Task { print((await OpenApps.close(except ? [] : names, keep: except ? names : nil)).text); exit(0) }
            RunLoop.main.add(Timer(timeInterval: 60, repeats: true) { _ in }, forMode: .default); CFRunLoopRun(); return
        }
        if CommandLine.arguments.contains("--activity-test") {
            Task { await ActivityTests.run(); exit(0) }
            RunLoop.main.add(Timer(timeInterval: 60, repeats: true) { _ in }, forMode: .default); CFRunLoopRun(); return
        }
        if CommandLine.arguments.contains("--account-status") {
            Task { @MainActor in
                do {
                    guard let key = KeyStore.read() else { throw VoiceError.message("This app could not read its saved Keychain key.") }
                    let status = try await JevClient().accountStatus(key: key)
                    let data = try JSONSerialization.data(withJSONObject: status, options: [.prettyPrinted, .sortedKeys])
                    print(String(data: data, encoding: .utf8)!); exit(0)
                } catch { print(error.localizedDescription); exit(1) }
            }
            RunLoop.main.add(Timer(timeInterval: 60, repeats: true) { _ in }, forMode: .default); CFRunLoopRun(); return
        }
        if CommandLine.arguments.contains("--router-test") {
            Task { await SelfTests.router(); exit(0) }
            RunLoop.main.add(Timer(timeInterval: 60, repeats: true) { _ in }, forMode: .default); CFRunLoopRun()
            return
        }
        if arguments.contains("--help") || arguments.contains("-h") {
            printUsage(); exit(0)
        }
        let allowedGUIFlags: Set<String> = ["--diagnostics"]
        let unknownFlags = arguments.dropFirst().filter { $0.hasPrefix("-") && !allowedGUIFlags.contains($0) }
        if !unknownFlags.isEmpty {
            fputs("Unknown option: \(unknownFlags.joined(separator: ", "))\n", stderr)
            printUsage(); exit(2)
        }
        let bundleID = Bundle.main.bundleIdentifier ?? "ai.conductor.public"
        if let existing = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .first(where: { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }) {
            existing.activate(options: [.activateAllWindows])
            exit(0)
        }
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        withExtendedLifetime(delegate) { application.run() }
    }
}
