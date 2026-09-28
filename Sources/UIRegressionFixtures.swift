import AppKit
import SwiftUI
import QuartzCore

@MainActor enum UIRegressionFixtures {
    static func run(_ directory: URL) throws {
        UserDefaults.standard.setVolatileDomain(["brainEnabled": false, "whisperEnabled": false, "speechLocale": "en-US", "AppleLanguages": ["en"]], forName: UserDefaults.argumentDomain)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        _ = NSApplication.shared; NSApp.setActivationPolicy(.accessory)
        func model() -> AppModel {
            let value = AppModel()
            value.keyConfigured = true; value.accessibilityGranted = true
            value.microphoneGranted = true; value.speechGranted = true
            return value
        }
        let ready = model()
        let recognizing = model(); recognizing.phase = "Recognizing"
        let working = model(); working.busy = true; working.phase = "Thinking"
        working.transcript = "Explain the UI issues and save an agent error"
        working.detail = "Planning your request"
        let short = model(); short.transcript = "Did it save?"; short.answerText = "Your words are saved."; short.modelLabel = "GPT-6 Astra"
        let long = model(); long.transcript = "Help me describe the UI issues"; long.modelLabel = "GPT-6 Astra"
        long.answerText = "The text is difficult to read, the panels change width between states, and the spacing shifts when an answer opens. I’ll use one compact panel width and the same body text size throughout. Longer answers can scroll while the controls stay available."
        let failure = model(); failure.phase = "Needs attention"; failure.detail = "Speech recognition stopped. Your words are kept in the input. Review them before sending."
        let cases = [("ready", ready), ("recognizing", recognizing), ("working", working), ("short-answer", short), ("long-answer", long), ("failure", failure)]
        for (name, value) in cases {
            let size = CommandBarView.preferredSize(model: value)
            precondition(size.width == CommandBarView.width)
            let view = CommandBarView(model: value, openSettings: {}, releaseKeyboard: {})
                .environment(\.locale, Locale(identifier: "en"))
            let host = NSHostingView(rootView: view)
            let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false; window.backgroundColor = NSColor(Palette.panel)
            window.contentView = host; host.frame = NSRect(origin: .zero, size: size)
            host.layoutSubtreeIfNeeded(); RunLoop.main.run(until: Date().addingTimeInterval(0.12)); host.layoutSubtreeIfNeeded(); CATransaction.flush()
            guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { throw VoiceError.message("Cannot render " + name) }
            host.cacheDisplay(in: host.bounds, to: bitmap)
            try bitmap.representation(using: NSBitmapImageRep.FileType.png, properties: [:])!.write(to: directory.appendingPathComponent(name + ".png"))
            window.close()
            print("PASS: \(name), \(Int(size.width)) × \(Int(size.height)) points.")
        }
        let narrow = CommandBarView.preferredSize(model: long, maximumHeight: 300, maximumWidth: 300)
        precondition(narrow.width <= 300 && narrow.height <= 300)
        print("PASS: small-screen constraints preserved. Only owned sample UI was rendered.")
    }
}
