import AppKit
import SwiftUI
import QuartzCore

/// Sample text for the gallery (not main-actor isolated, so it can serve as default arguments).
private enum Sample {
    static let shortCommand = "Open Safari and show my calendar"
    static let mediumCommand = "Open the coordinator task in Codex, tell it the receipts work now, and read me its latest reply"
    static let longCommand = "Find the main coordinator session, tell it that messages sometimes stay unsent, and ask why each fix seems to open another gap. Then open Notes, make a list called Conductor follow-ups with three items: receipts, long dictation and the Claude sign-in, and pin it."
    static let veryLongCommand = Array(repeating: "I want to walk through everything that happened with the release today, so keep all of this. First the speech test failed because the timer fired late, then the receipts were fixed, and the Claude sign-in had to be renewed.", count: 7).joined(separator: " ") + " That is the end of the dictation."
    static let russianCommand = "Закрой все приложения, кроме Claude, и открой мне Telegram."
    static let shortAnswer = "Done. Safari is open with your calendar."
    static let mediumAnswer = "Opened the coordinator task in Codex and sent your message. Its latest reply says the receipt check now reads the app's own page, so a preview panel no longer hides the task title."
    static let longAnswer = """
    Here is what changed today.

    Brain timeouts now expire only after real silence, so a long task is no longer cut off while it is still working. Stop ends the model process at once.

    Messages sent to a Codex or Claude task are confirmed by the task's saved history, or by the exact message on screen with no draft left. If neither appears within eight seconds, the request stays unfinished and I say so.

    Long dictation is no longer cut at two minutes, and your words survive recognizer errors.
    """
    static let veryLongAnswer = Array(repeating: Sample.longAnswer, count: 3).joined(separator: "\n\n")
    static let russianAnswer = "Открыл в Chrome Википедию, GitHub и Hacker News."
    static let usageLine = "This command: 54.9k input / 282 output tokens · $0.122 at API list price · Plan usage: 5-hour window 3%, week 0%"
    static let dayLine = "Today: 4 commands, 168.0k / 1.1k tokens, $0.12 at API list price"

}

/// Every command-panel, settings, practice and menu state, rendered offscreen with sample data:
/// `Conductor --render-ui-gallery folder [--language ru]`. No microphone, network, model request,
/// screen capture or saved-setting change. Run it as the signed app (`open -n -W … --args …`) so
/// macOS permissions and the Keychain match the installed app. Writes one PNG per state and
/// `gallery.json` (file, group, title, when the state appears, size in points).
@MainActor enum UIGallery {
    private struct Entry: Codable { let file: String; let group: String; let title: String; let when: String; let points: String }
    private static var entries: [Entry] = []
    private static var folder = URL(fileURLWithPath: "/")
    private static var base: [String: Any] = [:]
    private static var language = "en"
    /// A second language renders only the states whose text differs most.
    private static var coreOnly = false

    static func run(_ directory: URL, language: String) throws {
        folder = directory; self.language = language; coreOnly = language != "en"
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        _ = NSApplication.shared; NSApp.setActivationPolicy(.accessory)
        base = [
            "AppleLanguages": [language], "speechLocale": "en-US", "brainModel": "sonnet", "brainEnabled": true,
            // An enabled Claude brain warms its CLI when a model is created; /usr/bin/true exits at once.
            "claudeCLIPath": "/usr/bin/true", "whisperEnabled": false, "diagnosticsEnabled": false,
            "continuousListening": false, "sendByWord": true, "voiceFeedback": false,
            "agentStatusCommand": [String](), "usageSummaryCommand": [String](),
        ]
        try commandBar()
        try settings()
        if !coreOnly { try practice(); try menus(); try artwork(); try readme() }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
        try encoder.encode(entries).write(to: directory.appendingPathComponent("gallery.json"))
        print("Rendered \(entries.count) states into \(directory.path)")
    }

    private static func model(_ overrides: [String: Any] = [:], micOn: Bool = false, queued: [String] = [], jev: [JevCallRecord] = []) -> AppModel {
        UserDefaults.standard.setVolatileDomain(base.merging(overrides) { $1 }, forName: UserDefaults.argumentDomain)
        let value = AppModel()
        value.stageForGallery(micOn: micOn, queued: queued, jevCalls: jev)
        value.keyConfigured = true; value.accessibilityGranted = true
        value.microphoneGranted = true; value.speechGranted = true; value.localSpeechAvailable = true
        value.agentsOK = true; value.agentsSummary = ""
        return value
    }

    // MARK: Rendering

    private static func save<V: View>(_ view: V, size: NSSize, group: String, name: String, title: String, when: String, backdrop: Bool, core: Bool,
                                      backdropColor: Color = Color(red: 0.40, green: 0.42, blue: 0.46)) throws {
        guard !coreOnly || core else { return }
        let file = String(format: "%03d-%@.png", entries.count + 1, name)
        let pad: CGFloat = backdrop ? 28 : 0
        let canvas = NSSize(width: size.width + pad * 2, height: size.height + pad * 2)
        let content = ZStack {
            if backdrop { backdropColor }
            view.frame(width: size.width, height: size.height)
                .shadow(color: .black.opacity(backdrop ? 0.4 : 0), radius: 16, y: 6)
        }.frame(width: canvas.width, height: canvas.height).environment(\.locale, Locale(identifier: language))
        let host = NSHostingView(rootView: content)
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: canvas), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.backgroundColor = NSColor(Palette.panel)
        window.contentView = host; host.frame = NSRect(origin: .zero, size: canvas)
        host.layoutSubtreeIfNeeded(); RunLoop.main.run(until: Date().addingTimeInterval(0.15)); host.layoutSubtreeIfNeeded(); CATransaction.flush()
        guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { throw VoiceError.message("Cannot render " + file) }
        host.cacheDisplay(in: host.bounds, to: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:]) else { throw VoiceError.message("Cannot encode " + file) }
        try png.write(to: folder.appendingPathComponent(file))
        window.close()
        entries.append(Entry(file: file, group: group, title: title, when: when, points: "\(Int(size.width)) × \(Int(size.height))"))
    }

    private static func bar(_ name: String, _ title: String, _ when: String, _ m: AppModel, typing: Bool = false, details: Bool = false,
                            collapsed: Bool = false, width: CGFloat = 600, height: CGFloat = 520, core: Bool = false,
                            group: String = "Command panel", backdropColor: Color = Color(red: 0.40, green: 0.42, blue: 0.46)) throws {
        let limits = CommandSurfaceLimits(); limits.width = width; limits.height = height
        let size = CommandBarView.preferredSize(model: m, typing: typing, details: details, maximumHeight: height, maximumWidth: width, attentionCollapsed: collapsed)
        let view = CommandBarView(model: m, openSettings: {}, releaseKeyboard: {}, initiallyEditing: typing, initiallyShowsDetails: details,
                                  limits: limits, initiallyAttentionCollapsed: collapsed)
        try save(view, size: size, group: group, name: "panel-" + name, title: title, when: when, backdrop: true, core: core, backdropColor: backdropColor)
    }

    // MARK: Command panel

    private static func commandBar() throws {
        try bar("idle-ready", "Idle: ready", "No task and the mic is off: after launch, after closing an answer, between commands. The label is the engine state, the hint says how to speak.", model(), core: true)
        let micOn = model(micOn: true)
        try bar("idle-mic-on", "Idle: mic on, not capturing", "The listening session is on (continuous mode or one-shot) but no speech is being captured at this moment. Hint reads ‘Mic on’; the mic button turns red.", micOn)
        let agents = model(); agents.agentsOK = false
        try bar("idle-agent-warning", "Idle: local agents need attention", "A configured local agent-status command reported a problem: the ⋯ menu button turns red. Nothing else explains why.", agents)

        func holding(_ text: String, level: Double = 0.35) -> AppModel {
            let m = model(); m.holdingToTalk = true; m.phase = "Listening"; m.liveTranscript = text; m.level = level; return m
        }
        try bar("listening-fn-empty", "Listening (Fn held): nothing heard yet", "Fn or right Option is held and no words are recognized yet.", holding(""), core: true)
        try bar("listening-fn-short", "Listening (Fn held): short transcript", "Words appear live as they are recognized. Release Fn to send.", holding(Sample.shortCommand, level: 0.8), core: true)
        try bar("listening-fn-medium", "Listening (Fn held): about 100 characters", "Up to 120 characters stay in the top area.", holding(Sample.mediumCommand))
        try bar("listening-fn-long", "Listening (Fn held): long transcript", "Over 120 characters the transcript moves into a scrolling area under the header.", holding(Sample.longCommand), core: true)
        try bar("listening-fn-very-long", "Listening (Fn held): very long dictation", "A two-minute dictation: the panel reaches its maximum height and the transcript scrolls.", holding(Sample.veryLongCommand))
        try bar("listening-fn-russian", "Listening (Fn held): Russian speech", "Speech language Russian (or mixed words): Cyrillic transcript in the English interface.", holding(Sample.russianCommand))
        let tap = model(micOn: true); tap.listening = true; tap.tapListening = true; tap.phase = "Listening"; tap.liveTranscript = Sample.shortCommand
        try bar("listening-tap-mode", "Listening after a short Fn tap", "A short tap starts listening until the next tap or ‘end command’.", tap)
        let pause = model(["continuousListening": true, "sendByWord": false], micOn: true); pause.listening = true; pause.phase = "Listening"; pause.liveTranscript = Sample.shortCommand
        try bar("listening-continuous-pause", "Continuous listening, send after a pause", "Settings › Voice › Continuous with ‘After a pause’: a pause sends the request.", pause)
        let word = model(["continuousListening": true, "sendByWord": true], micOn: true); word.listening = true; word.phase = "Listening"
        try bar("listening-continuous-word", "Continuous listening, send by phrase", "Continuous with ‘After end command or Fn’, nothing said yet.", word)
        let oneShot = model(micOn: true); oneShot.listening = true; oneShot.phase = "Listening"; oneShot.liveTranscript = "Open Notes"
        try bar("listening-one-shot", "Listening for one command (Option-Space or mic button)", "One command, sent after a pause.", oneShot)

        func recognizing(_ text: String) -> AppModel { let m = model(); m.phase = "Recognizing"; m.liveTranscript = text; return m }
        try bar("recognizing-empty", "Recognizing: finishing the transcript", "Fn released; the final transcript is not ready yet (Apple Speech or local Whisper).", recognizing(""), core: true)
        try bar("recognizing-short", "Recognizing with a short transcript", "Same moment, words already visible.", recognizing(Sample.shortCommand))
        try bar("recognizing-long", "Recognizing with a long transcript", "Long transcripts use the scrolling area.", recognizing(Sample.longCommand))

        func busy(_ phase: String, _ detail: String, command: String = Sample.russianCommand) -> AppModel {
            let m = model(); m.busy = true; m.phase = phase; m.detail = detail; m.transcript = command; return m
        }
        try bar("thinking", "Thinking", "The selected brain is planning. The heard request is shown above the status.", busy("Thinking", "Claude Sonnet 5.5 is thinking…"), core: true)
        try bar("thinking-long-request", "Thinking with a long request", "The request is clamped to two lines while working.", busy("Thinking", "Claude Sonnet 5.5 is thinking…", command: Sample.longCommand))
        try bar("brain-tool-work", "Brain working on the Mac", "The brain runs its own tools (shell, AppleScript). The artwork still shows Thinking.", busy("Thinking", "Working on your Mac: Close every app except Claude"))
        try bar("acting-jev-step", "Acting: a Jev UI step", "Jev performs one visible UI action (click, type, press).", busy("Acting", "Click New Tab", command: "В Chrome открой мне Википедию, GitHub и Hacker News."), core: true)
        try bar("observing-no-brain", "Acting without a brain", "Brain turned off (Plan before acting off): Jev reads the screen directly.", busy("Observing", "Reading available actions…", command: Sample.shortCommand))
        try bar("checking", "Checking the result", "After the actions the brain looks at the screen to judge the whole request.", busy("Thinking", "Checking the result…"), core: true)
        let longDetail = busy("Acting", "Jev is choosing between 184 controls in Google Chrome: the tab strip, the address bar, bookmarks and the page itself. This round asks which control opens a new tab without closing the current page, then types the address and presses Return.")
        try bar("working-long-status", "Working with a long status line", "A status over 180 characters moves into the scrolling area.", longDetail)
        let queue = busy("Acting", "Type “https://wikipedia.org”"); queue.shotsThisCommand = 3
        queue.stageForGallery(queued: ["Open Telegram", "Read me the latest reply from the coordinator"])
        try bar("busy-queue-and-screenshots", "Working with queued requests and screenshots", "Requests spoken or typed while busy wait in a queue (up to 8); the camera count shows screenshots sent to the brain.", queue)
        let nextEmpty = busy("Thinking", "Claude Sonnet 5.5 is thinking…"); nextEmpty.holdingToTalk = true
        try bar("busy-listening-next-empty", "Working and listening to the next request", "Fn held while a task runs: the next request will be queued.", nextEmpty)
        let nextText = busy("Thinking", "Claude Sonnet 5.5 is thinking…"); nextText.holdingToTalk = true; nextText.liveTranscript = "Then open Telegram and read me the newest message"; nextText.level = 0.7
        try bar("busy-listening-next-text", "Working and listening, with words", "The next request's live transcript uses the scrolling area.", nextText, core: true)
        let busyTyping = busy("Thinking", "Claude Sonnet 5.5 is thinking…"); busyTyping.typedCommand = "Also mute Slack"
        try bar("busy-typing-queue", "Typing a request while working", "The keyboard button opens the editor; while busy it adds to the queue.", busyTyping, typing: true)

        func answer(_ text: String, command: String = Sample.shortCommand, label: String = "Claude Sonnet 5.5") -> AppModel {
            let m = model(); m.phase = "Done"; m.transcript = command; m.answerText = text; m.modelLabel = label
            m.usageLine = Sample.usageLine; m.dayLine = Sample.dayLine; m.contextUsed = 11_664; return m
        }
        try bar("answer-short", "Answer: short", "A short answer fits beside the artwork.", answer(Sample.shortAnswer), core: true)
        try bar("answer-short-details", "Answer: short, details open", "Details shows tokens, cost at API list price, plan usage and the conversation bar.", answer(Sample.shortAnswer), details: true)
        try bar("answer-medium", "Answer: medium", "Longer answers move under the header with a footer of controls.", answer(Sample.mediumAnswer, command: Sample.mediumCommand), core: true)
        try bar("answer-long", "Answer: long", "Multi-paragraph answer, scrolls inside the panel.", answer(Sample.longAnswer, command: "What changed in Conductor today?"))
        try bar("answer-very-long", "Answer: very long", "Maximum panel height; the answer scrolls.", answer(Sample.veryLongAnswer, command: "What changed in Conductor today?"))
        let rich = answer(Sample.shortAnswer)
        rich.shotsThisCommand = 2; rich.shotsToday = 9; rich.contextUsed = 30_500
        rich.lastScreenshot = Bundle.main.url(forResource: "thinking", withExtension: "png", subdirectory: "ConductorStates").flatMap(NSImage.init(contentsOf:))
        rich.limitShare = LocalIntegrations.LimitShare(commandPercent: 0.8, jevPercent: 6.5, fiveHour: 23, week: 41, resets: Date().addingTimeInterval(7_200), commandUSD: 0.12, percentPerDollar: 6.6)
        try bar("answer-details-full", "Answer: details with limit share and screenshot", "Details with the optional five-hour limit share, the latest screenshot sent to the brain and a context bar past 60%.", rich, details: true)
        let restart = answer("Started a new conversation.", command: "Restart yourself please."); restart.contextUsed = 0
        try bar("answer-new-conversation", "Answer: new conversation (details open)", "‘Start over’ or ‘restart yourself’: the brain's memory is cleared.", restart, details: true)
        let full = answer(Sample.shortAnswer); full.contextUsed = 42_000
        try bar("answer-context-full", "Answer: conversation nearly full", "Context past 85% of the budget: the bar turns red and suggests a new conversation.", full, details: true)
        try bar("answer-russian", "Answer in Russian", "Answers follow the language of the request.", answer(Sample.russianAnswer, command: "В Chrome открой мне Википедию, GitHub и Hacker News.", label: "GPT-5.6 Terra"), core: true)
        try bar("answer-fallback-model", "Answer from a fallback model", "A model label containing ‘fallback’ is shown in red (reserved for automatic model fallback).", answer(Sample.shortAnswer, label: "GPT-6 Astra (fallback)"))

        func attention(_ detail: String, phase: String = "Needs attention") -> AppModel { let m = model(); m.phase = phase; m.detail = detail; return m }
        let brainError = attention("Claude: Your organization has disabled Claude subscription access for Claude Code · Use an Anthropic API key instead, or ask your admin to enable access")
        brainError.transcript = "Закрой все приложения, кроме Клода. Пожалуйста."
        brainError.answerText = "Could not complete the request: Your organization has disabled Claude subscription access for Claude Code · Use an Anthropic API key instead, or ask your admin to enable access"
        try bar("error-brain-with-answer", "Error: brain failed (attention plus answer)", "A brain error sets Needs attention and also shows the error as an answer, so the same text appears twice (seen in real use on 2026-09-28).", brainError, core: true)
        try bar("error-timeout", "Error: no activity from the brain", "The brain produced nothing for the idle limit; the request is unfinished.", attention("Codex produced no activity for 180 seconds. The request is unfinished."))
        try bar("error-receipt-unconfirmed", "Error: message not confirmed", "A message typed into a Codex or Claude task could not be confirmed within 8 seconds.", attention("The message could not be confirmed in the intended Codex task. The request remains unfinished; check its draft before retrying to avoid sending twice."))
        let draft = attention("Speech recognition stopped: The audio device stopped or changed. Your words are kept in the input. Review them before sending.")
        draft.typedCommand = Sample.longCommand
        try bar("error-speech-interrupted-draft", "Error: speech interrupted, words kept", "Recognition stopped mid-request; the words so far are kept and the editor opens on them.", draft, typing: true, core: true)
        try bar("error-mic-unavailable", "Microphone unavailable", "The input device failed and could not be restarted; typed commands still work.", attention("Microphone unavailable. Text commands still work. Reconnect your microphone and turn listening on.", phase: "Ready"))
        try bar("error-reconnecting-mic", "Reconnecting the microphone", "The audio device changed; Conductor retries.", attention("The audio device stopped or changed. Turn the mic on to reconnect.", phase: "Reconnecting microphone"))
        let access = attention("Approve macOS Microphone and Speech Recognition access; listening will start automatically.", phase: "Allow voice access"); access.requestingAudio = true
        try bar("permission-voice-request", "Asking for microphone access", "First use: waiting for the macOS Microphone and Speech Recognition prompts.", access, core: true)
        let noKey = model(); noKey.keyConfigured = false
        try bar("setup-no-key", "Setup: no Jev key", "No TypeSafe or OpenRouter key saved.", noKey, core: true)
        let noAX = model(); noAX.accessibilityGranted = false
        try bar("setup-no-accessibility", "Setup: no Accessibility", "Conductor is not allowed to control apps.", noAX)
        let noBoth = model(); noBoth.keyConfigured = false; noBoth.accessibilityGranted = false
        try bar("setup-key-and-accessibility", "Setup: key and Accessibility missing", "First launch on a new Mac.", noBoth)
        let billing = model(); billing.billingIssue = "TypeSafe reported a billing problem for this API key. Check your TypeSafe account, then check the connection and repeat your request."
        try bar("error-billing", "Billing problem with the Jev key", "The Jev provider refused the key for billing reasons (HTTP 402).", billing)
        try bar("attention-dismissed", "Attention dismissed", "The × on an attention message collapses it; an Open Settings link stays.", attention("Codex produced no activity for 180 seconds. The request is unfinished."), collapsed: true)

        try bar("typing-empty", "Typing a request", "The keyboard button or ‘Type a request’ opens the editor; the panel widens to 500 points.", model(), typing: true, core: true)
        let typed = model(); typed.typedCommand = "Open Notes and create a shopping list"
        try bar("typing-with-text", "Typing a request with text", "Return or the arrow button runs it.", typed, typing: true)

        try bar("narrow-screen-answer", "Narrow screen: answer", "Screens under 320 points of free width stack the artwork above the text.", answer(Sample.mediumAnswer, command: Sample.mediumCommand), width: 300, height: 520)
        try bar("short-screen-long-answer", "Short screen: long answer", "A short visible screen area limits the panel height; the answer scrolls.", answer(Sample.longAnswer, command: "What changed in Conductor today?"), height: 300)
    }

    // MARK: Settings

    private static func settings() throws {
        func page(_ name: String, _ title: String, _ when: String, _ m: AppModel, section: String? = nil, guide: Bool = false, step: Int = 0,
                  height: CGFloat = 680, core: Bool = false) throws {
            let view = SettingsView(model: m, initialSection: section, initiallyShowsGuide: guide, initialGuideStep: step)
            try save(view, size: NSSize(width: 840, height: height), group: "Settings window", name: "settings-" + name, title: title, when: when, backdrop: false, core: core)
        }
        let fresh = model(); fresh.keyConfigured = false; fresh.microphoneGranted = false; fresh.speechGranted = false
        try page("guide-1-brain", "Setup guide 1: brain", "Opens automatically on first launch while a key or a permission is missing; also Settings › Setup guide.", fresh, guide: true, step: 0, core: true)
        try page("guide-2-connection", "Setup guide 2: Jev connection", "Key entry for TypeSafe or OpenRouter.", fresh, guide: true, step: 1)
        try page("guide-3-mac-access", "Setup guide 3: Mac access", "Permission rows open the real macOS prompts.", fresh, guide: true, step: 2)
        try page("guide-4-try-it", "Setup guide 4: try it", "Points to the practice window.", fresh, guide: true, step: 3)
        try page("voice-hold-fn", "Voice: hold Fn (default)", "Settings opens on Voice.", model(), section: "Voice", core: true)
        try page("voice-continuous-russian", "Voice: continuous, send by phrase, Russian", "Continuous listening shows a second picker; Russian speech selected.", model(["continuousListening": true, "sendByWord": true, "speechLocale": "ru-RU"]), section: "Voice")
        let noSpeech = model(); noSpeech.localSpeechAvailable = false
        try page("voice-speech-unavailable", "Voice: Apple Speech unavailable", "Dictation is off in System Settings.", noSpeech, section: "Voice")
        let ready = model(); ready.connectionDetail = "Jev is ready: TypeSafe answered in 612 ms with a real decision."
        try page("connections-ready", "Connections: key saved, brain chosen", "Brain list with the selected model; Jev key status and connection check.", ready, section: "Connections", height: 900, core: true)
        let noKey = model(); noKey.keyConfigured = false
        try page("connections-no-key", "Connections: no key", "Key entry field and a disabled check.", noKey, section: "Connections", height: 900)
        let checking = model(); checking.checkingConnection = true; checking.connectionDetail = "Checking Jev through TypeSafe…"
        try page("connections-checking", "Connections: checking", "While the connection check runs.", checking, section: "Connections", height: 900)
        try page("connections-brain-off", "Connections: brain turned off", "Plan before acting off: model rows are disabled.", model(["brainEnabled": false, "claudeCLIPath": ""]), section: "Connections", height: 900)
        let billing = model(); billing.billingIssue = "TypeSafe reported a billing problem for this API key. Check your TypeSafe account, then check the connection and repeat your request."
        try page("connections-billing", "Connections: billing problem banner", "A billing refusal shows a red banner at the top of every section.", billing, section: "Connections", height: 900)
        try page("access-all-granted", "Access: all granted", "Screen Recording reflects the rendering process's real permission.", model(), section: "Access", core: true)
        let missing = model(); missing.microphoneGranted = false; missing.speechGranted = false; missing.accessibilityGranted = false
        try page("access-missing", "Access: permissions missing", "Open Settings buttons for missing permissions.", missing, section: "Access")
        let advanced = model(["brainEnabled": false, "claudeCLIPath": ""]); advanced.contextUsed = 11_664; advanced.brainTurns = 4
        advanced.usageLine = Sample.usageLine; advanced.dayLine = Sample.dayLine; advanced.agentsSummary = "Claude Code, Codex and Hermes: 3 sessions running, no errors."
        try page("advanced", "Advanced: paths, local agents, conversation, privacy", "Full height; the real window scrolls from 680 points.", advanced, section: "Advanced", height: 1_340, core: true)
        try page("jev-activity-empty", "Jev activity: no calls yet", "Before the first Jev call in this app session.", model(), section: "Jev activity")
        let calls = model(jev: sampleCalls())
        try page("jev-activity-calls", "Jev activity: calls with JSON", "The latest call is followed; input, output and observed result tabs.", calls, section: "Jev activity", height: 1_040)
    }

    private static func sampleCalls() -> [JevCallRecord] {
        var pick = JevCallRecord(stage: "Round 1 · Choose action", command: "В Chrome открой мне Википедию и GitHub", input: "{\"request\":\"Open Wikipedia and GitHub in Chrome\",\"options\":[{\"id\":1,\"label\":\"New Tab\"},{\"id\":2,\"label\":\"Address and search bar\"}]}", optionCount: 184)
        pick.output = "{\"choice\":1,\"probability\":0.93,\"model\":\"jev-1\"}"; pick.httpStatus = 200; pick.milliseconds = 412; pick.answers = "New Tab"; pick.outcome = "Clicked New Tab. Screen state changed."
        var typing = JevCallRecord(stage: "Round 2 · Choose typing payload", command: "В Chrome открой мне Википедию и GitHub", input: "{\"request\":\"Type the address\"}", optionCount: 2)
        typing.output = "{\"choice\":\"wikipedia.org\"}"; typing.httpStatus = 200; typing.milliseconds = 388; typing.answers = "wikipedia.org"
        var failed = JevCallRecord(stage: "Round 3 · Verify completion", command: "В Chrome открой мне Википедию и GitHub", input: "{\"request\":\"Is the page open?\"}", optionCount: 2)
        failed.error = "The request timed out."; failed.milliseconds = 15_000
        let pending = JevCallRecord(stage: "Connection check", command: "Connection check", input: "{\"request\":\"ready?\"}", optionCount: 1)
        return [pick, typing, failed, pending]
    }

    // MARK: Practice, menus, artwork

    private static func practice() throws {
        try save(PracticeView(model: model()), size: NSSize(width: 475, height: 465), group: "Practice window", name: "practice-window",
                 title: "Practice window", when: "Setup guide step 4 › Open practice window: safe buttons and a field to try voice control.", backdrop: false, core: false)
    }

    private struct MenuMock: View {
        struct Row { var title = ""; var check = false; var disabled = false; var indent = false; var separator = false; var shortcut = "" }
        let rows: [Row]
        var body: some View {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    if row.separator { Rectangle().fill(Color.white.opacity(0.12)).frame(height: 1).padding(.vertical, 5).padding(.horizontal, 10) }
                    else {
                        HStack(spacing: 6) {
                            Text(row.check ? "✓" : "").frame(width: 12)
                            Text(row.title).padding(.leading, row.indent ? 14 : 0)
                            Spacer(minLength: 24)
                            if !row.shortcut.isEmpty { Text(row.shortcut).foregroundStyle(Color.white.opacity(0.45)) }
                        }.font(.system(size: 13)).foregroundStyle(row.disabled ? Color.white.opacity(0.4) : Color.white.opacity(0.9))
                            .padding(.horizontal, 8).frame(height: 22)
                    }
                }
            }.padding(.vertical, 5).frame(width: 430)
                .background(Color(white: 0.17), in: RoundedRectangle(cornerRadius: 9))
                .overlay(RoundedRectangle(cornerRadius: 9).stroke(Color.white.opacity(0.14)))
        }
    }

    private static func menuHeight(_ rows: [MenuMock.Row]) -> CGFloat {
        let items = rows.filter { !$0.separator }.count, separators = rows.count - items
        return CGFloat(items) * 22 + CGFloat(separators) * 11 + 10
    }

    private static func menus() throws {
        typealias Row = MenuMock.Row
        var status: [Row] = [Row(title: "Show command bar"), Row(title: "Settings…", shortcut: "⌘,"), Row(title: "Agent dashboard"), Row(separator: true), Row(title: "Brain", disabled: true)]
        for choice in BrainChoice.all { status.append(Row(title: choice.name + "  ·  " + choice.short, check: choice.id == "sonnet", indent: true)) }
        status += [Row(title: "Start new conversation"), Row(title: "Check a recording…"), Row(title: "Run commands from a recording…"), Row(separator: true),
                   Row(title: "Speak answers"), Row(title: "Continuous listening"), Row(title: "Listen for one command (⌥ Space), or hold Fn"), Row(separator: true),
                   Row(title: "Hide command bar"), Row(title: "Quit Conductor", shortcut: "⌘Q")]
        try save(MenuMock(rows: status), size: NSSize(width: 430, height: menuHeight(status)),
                 group: "Menus (reconstructed)", name: "menu-bar-status-menu", title: "Menu bar icon menu (reconstruction)",
                 when: "Click the Conductor icon in the macOS menu bar. Real NSMenu; drawn here from Main.swift menuNeedsUpdate, not captured.", backdrop: true, core: false)
        var more: [Row] = [Row(title: "Claude Sonnet 5.5", disabled: true), Row(separator: true)]
        for choice in BrainChoice.all { more.append(Row(title: (choice.id == "sonnet" ? "✓ " : "    ") + choice.name + "  ·  " + choice.short)) }
        more += [Row(separator: true), Row(title: "Type a request"), Row(title: "Start new conversation"), Row(title: "Agent dashboard"), Row(title: "Settings…")]
        try save(MenuMock(rows: more), size: NSSize(width: 430, height: menuHeight(more)),
                 group: "Menus (reconstructed)", name: "menu-panel-more", title: "Command panel More (…) menu (reconstruction)",
                 when: "The ⋯ button on the command panel. SwiftUI Menu in Views.swift controls(); drawn here, not captured.", backdrop: true, core: false)
        let states: [VoiceState] = [.ready, .listening, .recognizing, .thinking, .acting, .checking, .attention]
        let strip = HStack(spacing: 22) {
            ForEach(states, id: \.self) { state in
                VStack(spacing: 8) {
                    Image(systemName: state.icon).font(.system(size: 18)).foregroundStyle(.white)
                    Text(state.rawValue).font(.system(size: 11)).foregroundStyle(Color.white.opacity(0.7))
                }.frame(width: 76)
            }
        }.padding(18).background(Color(white: 0.12), in: RoundedRectangle(cornerRadius: 10))
        try save(strip, size: NSSize(width: 7 * 76 + 6 * 22 + 36, height: 86), group: "Menus (reconstructed)", name: "menu-bar-icons",
                 title: "Menu bar icon per state", when: "The status item's SF Symbol follows the engine state every 0.3 s; its tooltip shows phase and detail.", backdrop: true, core: false)
    }

    private static func artwork() throws {
        let states: [VoiceState] = [.ready, .listening, .recognizing, .thinking, .acting, .checking, .attention]
        let sheet = HStack(alignment: .bottom, spacing: 14) {
            ForEach(states, id: \.self) { state in
                VStack(spacing: 8) {
                    ConductorStateView(state: state, animates: false).frame(width: 132, height: 97)
                    Text(state.rawValue).font(.system(size: 11)).foregroundStyle(Palette.muted)
                }
            }
        }.padding(20).background(Palette.panel, in: RoundedRectangle(cornerRadius: 14))
        try save(sheet, size: NSSize(width: 7 * 132 + 6 * 14 + 40, height: 97 + 8 + 14 + 40), group: "Artwork", name: "artwork-all-states",
                 title: "Conductor artwork for each state (posters)", when: "Resources/ConductorStates: one looping silent video per state (posters shown here); 220 ms crossfade between states.", backdrop: true, core: false)
    }

    // MARK: README

    /// One English request followed from start to finish on the README's dark background (14, 14, 14).
    /// `scripts/readme_flow.py` joins these into `assets/flow.png`.
    private static func readme() throws {
        let dark = Color(red: 14/255, green: 14/255, blue: 14/255)
        let command = Sample.shortCommand
        func step(_ name: String, _ title: String, _ m: AppModel) throws {
            try bar("readme-" + name, title, "README flow: " + title.lowercased() + ".", m, group: "README", backdropColor: dark)
        }
        let listening = model(); listening.holdingToTalk = true; listening.phase = "Listening"; listening.liveTranscript = command; listening.level = 0.8
        try step("listening", "Listening", listening)
        func busy(_ phase: String, _ detail: String) -> AppModel {
            let m = model(); m.busy = true; m.phase = phase; m.detail = detail; m.transcript = command; return m
        }
        try step("thinking", "Thinking", busy("Thinking", "Claude Sonnet 5.5 is thinking…"))
        try step("acting", "Acting", busy("Acting", "Click Calendar"))
        let done = model(); done.phase = "Done"; done.transcript = command; done.answerText = Sample.shortAnswer; done.modelLabel = "Claude Sonnet 5.5"
        done.usageLine = Sample.usageLine; done.dayLine = Sample.dayLine; done.contextUsed = 11_664
        try step("answer", "Answer", done)
    }
}
