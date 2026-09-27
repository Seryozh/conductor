import AppKit
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
    var answer: NSPanel!
    var practice: NSWindow?
    var statusItem: NSStatusItem!
    var hotkey: GlobalHotKey!
    var holdToTalk: HoldToTalkMonitor!
    var barHidden = false
    var pointerGeneration = 0
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 690, height: 650), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = NSLocalizedString("Jev Settings", comment: "Settings window title")
        window.titlebarAppearsTransparent = true
        window.backgroundColor = NSColor(Palette.background)
        window.contentView = NSHostingView(rootView: SettingsView(model: model))
        window.isReleasedWhenClosed = false
        window.center()
        overlay = CommandBarPanel(contentRect: NSRect(x: 0, y: 0, width: CommandBarView.width, height: 60), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        overlay.title = NSLocalizedString("Jev command bar", comment: "Command bar window title")
        overlay.isOpaque = false; overlay.backgroundColor = .clear; overlay.hasShadow = true
        overlay.level = .floating; overlay.hidesOnDeactivate = false
        overlay.isFloatingPanel = true; overlay.becomesKeyOnlyIfNeeded = true
        overlay.isMovableByWindowBackground = true
        overlay.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        overlay.tabbingMode = .disallowed
        overlay.contentView = NSHostingView(rootView: CommandBarView(model: model,
            openSettings: { [weak self] in self?.showSettings() },
            releaseKeyboard: { [weak self] in self?.releaseBarKeyboard() }))
        answer = CommandBarPanel(contentRect: NSRect(x: 0, y: 0, width: 488, height: 120), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        answer.title = NSLocalizedString("Jev answer", comment: "Answer window title")
        answer.isOpaque = false; answer.backgroundColor = .clear; answer.hasShadow = true
        answer.level = .floating; answer.hidesOnDeactivate = false
        answer.isFloatingPanel = true; answer.becomesKeyOnlyIfNeeded = true
        answer.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        answer.contentView = NSHostingView(rootView: AnswerView(model: model))
        model.showAnswer = { [weak self] in self?.presentAnswer() }
        model.hideAnswer = { [weak self] in self?.answer.orderOut(nil) }
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
        statusItem.button?.image = NSImage(systemSymbolName: "waveform", accessibilityDescription: NSLocalizedString("Jev Voice", comment: "Menu bar icon"))
        let menu = NSMenu()
        menu.delegate = self   // rebuilt on every open, so the checkmarks are current
        statusItem.menu = menu
        let mainMenu = NSMenu()
        let appMenu = NSMenu(); let appItem = NSMenuItem(); appItem.submenu = appMenu
        appMenu.addItem(withTitle: NSLocalizedString("Quit Jev Voice", comment: "Quit menu item"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
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
                self.statusItem.button?.image = NSImage(systemSymbolName: self.model.voiceState.icon, accessibilityDescription: NSLocalizedString("Jev Voice", comment: "Menu bar icon") + ": " + self.model.voiceState.rawValue)
                self.statusItem.button?.toolTip = "Jev Voice · " + self.model.phase + " · " + self.model.detail
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
        menu.addItem(.separator())
        add("Brain", nil)
        for choice in BrainChoice.all {
            let blocked = choice.codex && CodexBrain.binary() == nil
            add(choice.name + "  ·  " + (blocked ? "Codex CLI not found" : choice.short), blocked ? nil : #selector(pickBrain(_:)), state: model.brainModel == choice.id, id: choice.id, indent: true)
        }
        add("Start new conversation", #selector(resetConversation))
        menu.addItem(.separator())
        add("Speak answers", #selector(toggleVoiceAnswers), state: model.voiceFeedback)
        add("Continuous listening", #selector(toggleContinuous), state: model.continuousListening)
        add("Listen for one command (⌥ Space), or hold Fn", #selector(listen))
        menu.addItem(.separator())
        add("Hide command bar", #selector(hideCommandBar))
        add("Quit Jev Voice", #selector(quit), key: "q")
    }
    @objc func pickBrain(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String, let choice = BrainChoice.find(id) else { return }
        model.selectBrain(choice, by: "menu")
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
            practice?.title = NSLocalizedString("Jev Voice · Practice", comment: "Practice window title")
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
        guard let overlay, let answer, !model.answerText.isEmpty else { return }
        // Height from the real text size, so long answers get room (up to 75% of the screen)
        // and short ones stay small; the text scrolls beyond that.
        let style = NSMutableParagraphStyle(); style.lineSpacing = AnswerView.lineSpacing
        let text = NSAttributedString(string: model.answerText, attributes: [.font: AnswerView.textFont, .paragraphStyle: style])
        let textHeight = ceil(text.boundingRect(with: NSSize(width: AnswerView.width - 2 * AnswerView.horizontalPadding - 6, height: .greatestFiniteMagnitude),
                                                options: [.usesLineFragmentOrigin, .usesFontLeading]).height)
        let usage: CGFloat = model.usageLine.isEmpty ? 0 : 36
        let extras: CGFloat = 28 + 22 + 10 + (model.shotsThisCommand > 0 ? 60 : 0) + 12 + usage + 30 + 8
        let screen = overlay.screen ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1400, height: 900)
        let height = min(visible.height * 0.75, textHeight + extras)
        let x = min(max(visible.minX + 8, overlay.frame.midX - AnswerView.width / 2), visible.maxX - AnswerView.width - 8)
        answer.setFrame(NSRect(x: x, y: max(visible.minY + 8, overlay.frame.minY - height - 8), width: AnswerView.width, height: height), display: true)
        answer.orderFrontRegardless()
    }
    func presentOverlay() {
        guard !barHidden, let overlay else { return }
        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main
        if let screen, !overlay.isVisible || !screen.visibleFrame.contains(CGPoint(x: overlay.frame.midX, y: overlay.frame.midY)) {
            overlay.setFrameOrigin(NSPoint(x: screen.visibleFrame.midX - overlay.frame.width / 2,
                y: screen.visibleFrame.maxY - overlay.frame.height - 12))
        }
        overlay.orderFrontRegardless()
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { showCommandCenter(); return false }
}

@main struct JevVoiceApp {
    @MainActor static func main() {
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
            Task { print(await LocalWhisper.shared.transcribe(wav.subdata(in: 44..<wav.count), language: "ru") ?? "NO ANSWER"); exit(0) }
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
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        withExtendedLifetime(delegate) { application.run() }
    }
}
