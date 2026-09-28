import AppKit
import SwiftUI

/// The floating command panel. A fixed bottom bar (the conductor, the state and your words, one primary
/// button) never moves or resizes; everything Conductor says back (progress, answer, attention, typing)
/// opens in one drawer above it. The window is anchored at its bottom edge, so the drawer grows upward.

/// Screen constraints belong to window presentation, never to the task engine.
@MainActor final class CommandSurfaceLimits: ObservableObject {
    @Published var width: CGFloat = 600
    @Published var height: CGFloat = 520
}

private struct PanelMotionKey: EnvironmentKey { static let defaultValue = true }
extension EnvironmentValues {
    /// Offscreen renders turn motion off so every capture shows a settled state.
    var panelMotion: Bool {
        get { self[PanelMotionKey.self] }
        set { self[PanelMotionKey.self] = newValue }
    }
}

/// What the panel shows for one moment of AppModel. Presentation only; AppModel stays the source of truth.
struct PanelState: Equatable {
    enum Primary: Equatable { case mic, micOn, live, stop, wait }
    enum Notice: Equatable { case setup, microphoneRequest, microphoneUnavailable, reconnecting, billing, general }
    enum Kind: Equatable { case idle, capture, recognize, work, answer, attention, collapsed }
    var kind: Kind
    var pose: VoiceState
    var eyebrow: String
    var primary: Primary
    var tone: Color
    var eyebrowIcon: String? = nil
    var meta: String? = nil
    var timer = false
    var meter = false
    /// The user's own words, shown verbatim.
    var words: String? = nil
    /// A localized placeholder when there are no words.
    var hint: String? = nil
    var wordsProminent = false
    var tail = false
    var shimmer = false
    var notice: Notice? = nil
    var work = false
    var answer = false
    var errorAnswer = false
    var settingsLink = false

    init(kind: Kind, pose: VoiceState, eyebrow: String, primary: Primary, tone: Color? = nil) {
        self.kind = kind; self.pose = pose; self.eyebrow = eyebrow; self.primary = primary
        self.tone = tone ?? pose.tone
    }

    static let failurePrefix = "Could not complete the request:"

    @MainActor static func isCapturing(_ model: AppModel) -> Bool {
        model.holdingToTalk || (model.listening && model.micEnabled)
    }
    @MainActor static func needsAttention(_ model: AppModel) -> Bool {
        model.requestingAudio || model.voiceState == .attention || model.detail.hasPrefix("Microphone unavailable")
            || model.billingIssue != nil || !model.keyConfigured || !model.accessibilityGranted
    }
    @MainActor static func setupMessage(_ model: AppModel) -> String {
        if !model.keyConfigured && !model.accessibilityGranted { return "Connect Jev and allow Mac access." }
        if !model.keyConfigured { return "Connect Jev in Settings." }
        return "Allow Mac access in Settings."
    }
    @MainActor static func captureInstruction(_ model: AppModel) -> String {
        if model.holdingToTalk { return model.busy ? "Release Fn to queue" : "Release Fn to send" }
        if model.tapListening || model.wordMode { return "Say ‘end command’ to send" }
        return "Pause to send"
    }

    @MainActor static func make(_ model: AppModel, collapsed: Bool) -> PanelState {
        let capturing = isCapturing(model)
        let recognizing = model.phase == "Recognizing"
        let quiet = !model.busy && !capturing && !recognizing
        let attention = quiet && needsAttention(model)
        let hasAnswer = quiet && !model.answerText.isEmpty
        let errorAnswer = hasAnswer && (model.voiceState == .attention || model.answerText.hasPrefix(failurePrefix))
        let setup = !model.keyConfigured || !model.accessibilityGranted
        let micUnavailable = model.detail.hasPrefix("Microphone unavailable")
        let resting: Primary = model.micEnabled ? .micOn : .mic
        let trimmed = model.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        let request: String? = trimmed.isEmpty ? nil : trimmed

        if capturing {
            var state = PanelState(kind: .capture, pose: .listening, eyebrow: "Listening", primary: .live)
            state.meta = captureInstruction(model); state.meter = true; state.tail = true; state.wordsProminent = true
            let live = model.liveTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
            if live.isEmpty { state.hint = "Go ahead, I'm listening." } else { state.words = live }
            state.work = model.busy
            return state
        }
        if recognizing {
            var state = PanelState(kind: .recognize, pose: .recognizing, eyebrow: "Recognizing", primary: .wait)
            let live = model.liveTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
            if live.isEmpty { state.hint = "Finishing your words…" } else { state.words = live }
            state.tail = true; state.shimmer = true; state.wordsProminent = true
            return state
        }
        if model.busy {
            let pose: VoiceState = model.voiceState == .checking ? .checking : model.voiceState == .thinking ? .thinking : .acting
            var state = PanelState(kind: .work, pose: pose, eyebrow: pose == .checking ? "Checking" : pose == .thinking ? "Thinking" : "Acting", primary: .stop)
            state.timer = true; state.work = true
            if let request { state.words = request } else { state.hint = "Working on your request" }
            return state
        }
        var notice: Notice?
        if attention && !collapsed {
            if setup { notice = .setup }
            else if model.requestingAudio { notice = .microphoneRequest }
            else if model.billingIssue != nil { notice = .billing }
            else if micUnavailable { notice = .microphoneUnavailable }
            else if model.phase == "Reconnecting microphone" { notice = .reconnecting }
            else if !errorAnswer { notice = .general }
        }
        if hasAnswer {
            var state = PanelState(kind: .answer, pose: errorAnswer ? .attention : .ready, eyebrow: errorAnswer ? "Needs attention" : "Done",
                                   primary: resting, tone: errorAnswer ? Palette.danger : Palette.success)
            state.eyebrowIcon = errorAnswer ? nil : "checkmark"
            if let request { state.words = request } else { state.hint = "Answer" }
            state.answer = true; state.errorAnswer = errorAnswer; state.notice = notice
            return state
        }
        if let notice {
            var state = PanelState(kind: .attention, pose: .attention, eyebrow: "Needs attention", primary: resting)
            state.notice = notice
            if let request, notice == .general { state.words = request }
            else {
                switch notice {
                case .setup: state.hint = "Open Settings to finish setup."
                case .microphoneRequest: state.hint = "Answer the macOS prompt to continue."
                case .microphoneUnavailable: state.hint = "Typed requests still work."
                case .reconnecting: state.hint = "Reconnecting…"
                case .billing: state.hint = "Check your Jev key in Settings."
                case .general: state.hint = model.typedCommand.isEmpty ? "Hold Fn to try again" : "Review your words, then send"
                }
            }
            return state
        }
        // A dismissed message leaves a way back only when Settings can fix it.
        if attention && (setup || model.billingIssue != nil) {
            var state = PanelState(kind: .collapsed, pose: .attention, eyebrow: "Needs attention", primary: resting)
            state.hint = setup ? "Open Settings to finish setup." : "Check your Jev key in Settings."
            state.settingsLink = true
            return state
        }
        var state = PanelState(kind: .idle, pose: .ready, eyebrow: model.micEnabled ? "Mic on" : "Ready", primary: resting,
                               tone: model.micEnabled ? Palette.listening : Palette.tertiary)
        state.hint = "Hold Fn to speak"
        return state
    }
}

extension VoiceState {
    var icon: String {
        switch self {
        case .ready: return "mic.slash"
        case .listening: return "mic.fill"
        case .recognizing: return "text.bubble"
        case .thinking: return "brain.head.profile"
        case .acting: return "hand.tap"
        case .checking: return "checkmark.circle"
        case .attention: return "exclamationmark.triangle"
        }
    }
    /// The same hue as the conductor's coat in this pose.
    var tone: Color {
        switch self {
        case .ready: return Palette.tertiary
        case .listening: return Palette.listening
        case .recognizing: return Palette.recognizing
        case .thinking: return Palette.thinking
        case .acting: return Palette.accent
        case .checking: return Palette.success
        case .attention: return Palette.danger
        }
    }
    var color: Color { tone }
}

private struct DrawerHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

struct CommandBarView: View {
    @ObservedObject var model: AppModel
    @ObservedObject private var limits: CommandSurfaceLimits
    @FocusState private var editing: Bool
    @State private var showEditor: Bool
    @State private var showDetails: Bool
    @State private var attentionCollapsed: Bool
    @State private var drawerContent: CGFloat
    @State private var workStarted = Date()
    @State private var lastReported: CGFloat = 0
    @State private var shrinkGeneration = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let openSettings: () -> Void
    let releaseKeyboard: () -> Void
    let resize: (NSSize) -> Void
    let animates: Bool
    static let width: CGFloat = 480
    static let barHeight: CGFloat = 120
    static var railHeight: CGFloat { barHeight }
    static let cornerRadius: CGFloat = 24

    init(model: AppModel, openSettings: @escaping () -> Void, releaseKeyboard: @escaping () -> Void,
         resize: @escaping (NSSize) -> Void = { _ in }, maximumHeight: CGFloat = 520,
         initiallyEditing: Bool = false, initiallyShowsDetails: Bool = false, limits: CommandSurfaceLimits? = nil,
         initiallyAttentionCollapsed: Bool = false, animates: Bool = true) {
        self.model = model
        self.openSettings = openSettings
        self.releaseKeyboard = releaseKeyboard
        self.resize = resize
        self.animates = animates
        let constraints = limits ?? CommandSurfaceLimits()
        if limits == nil { constraints.height = maximumHeight }
        self.limits = constraints
        _showEditor = State(initialValue: initiallyEditing)
        _showDetails = State(initialValue: initiallyShowsDetails)
        _attentionCollapsed = State(initialValue: initiallyAttentionCollapsed)
        _drawerContent = State(initialValue: Self.drawerHeight(model: model, typing: initiallyEditing, details: initiallyShowsDetails,
                                                               collapsed: initiallyAttentionCollapsed, width: min(Self.width, constraints.width)))
    }

    // MARK: Geometry

    static func stageSize(for width: CGFloat) -> CGSize {
        width >= 420 ? CGSize(width: 120, height: 96) : width >= 340 ? CGSize(width: 88, height: 70) : .zero
    }
    static func columnWidth(for width: CGFloat) -> CGFloat {
        let stage = stageSize(for: width).width
        return max(120, width - (stage > 0 ? 12 + stage + 16 : 16) - 16 - 40 - 16)
    }
    static func hasDrawer(_ state: PanelState, typing: Bool) -> Bool {
        state.notice != nil || state.work || state.answer || typing
    }
    /// The drawer's natural height, measured with the same view the panel shows.
    static func drawerHeight(model: AppModel, typing: Bool, details: Bool, collapsed: Bool, width: CGFloat) -> CGFloat {
        let state = PanelState.make(model, collapsed: collapsed)
        guard hasDrawer(state, typing: typing) else { return 0 }
        let host = NSHostingView(rootView: DrawerMeasure(model: model, state: state, typing: typing, details: details, width: width))
        return ceil(host.fittingSize.height)
    }
    static func preferredSize(model: AppModel, typing: Bool = false, details: Bool = false,
                              maximumHeight: CGFloat = 520, maximumWidth: CGFloat = 600, attentionCollapsed: Bool = false) -> NSSize {
        let width = min(Self.width, maximumWidth)
        let drawer = drawerHeight(model: model, typing: typing, details: details, collapsed: attentionCollapsed, width: width)
        let visible = min(drawer, max(0, maximumHeight - barHeight - 1))
        return NSSize(width: width, height: barHeight + (visible > 0 ? visible + 1 : 0))
    }

    private var panelWidth: CGFloat { min(Self.width, limits.width) }
    private var state: PanelState { PanelState.make(model, collapsed: attentionCollapsed) }
    private var drawerShown: Bool { Self.hasDrawer(state, typing: showEditor) }
    private var maximumDrawer: CGFloat { max(0, limits.height - Self.barHeight - 1) }
    private var visibleDrawer: CGFloat { drawerShown ? min(drawerContent, maximumDrawer) : 0 }
    private var targetHeight: CGFloat { Self.barHeight + (visibleDrawer > 0 ? visibleDrawer + 1 : 0) }
    private var motion: Animation? { animates && !reduceMotion ? .spring(response: 0.34, dampingFraction: 0.88) : nil }
    private var fade: Animation? { animates && !reduceMotion ? .easeInOut(duration: 0.2) : nil }
    private var attentionIdentity: String {
        model.phase + "|" + model.detail + "|" + String(model.keyConfigured) + "|" + String(model.accessibilityGranted) + "|" + (model.billingIssue ?? "")
    }

    // MARK: Actions

    private func typeInstead() {
        showEditor = true
        DispatchQueue.main.async { editing = true }
    }
    private func closeEditor() { editing = false; showEditor = false; releaseKeyboard() }
    private func submit() {
        editing = false
        releaseKeyboard()
        model.runTyped()
        if model.typedCommand.isEmpty { showEditor = false }
    }
    private func primaryAction() {
        if state.primary == .stop { model.cancelCurrentTask(); return }
        editing = false
        releaseKeyboard()
        model.toggleListening()
    }
    private func closeAnswer() {
        if state.errorAnswer { attentionCollapsed = true }
        model.dismissAnswer()
    }
    /// The window grows before the drawer opens and shrinks after it closes, so the bar never moves.
    private func report(_ height: CGFloat) {
        let size = NSSize(width: panelWidth, height: height)
        if height >= lastReported || motion == nil {
            shrinkGeneration += 1
            lastReported = height
            resize(size)
        } else {
            shrinkGeneration += 1
            let generation = shrinkGeneration
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                guard generation == shrinkGeneration else { return }
                lastReported = height
                resize(size)
            }
        }
    }

    // MARK: Body

    var body: some View {
        let current = state
        VStack(spacing: 0) {
            ScrollView(.vertical) {
                PanelDrawer(model: model, state: current, showsEditor: showEditor, showDetails: $showDetails, editing: $editing,
                            width: panelWidth, openSettings: openSettings, closeEditor: closeEditor, typeInstead: typeInstead,
                            submit: submit, dismissNotice: { attentionCollapsed = true }, closeAnswer: closeAnswer,
                            stop: { model.cancelCurrentTask() })
                    .background(GeometryReader { geometry in Color.clear.preference(key: DrawerHeightKey.self, value: geometry.size.height) })
                    .padding(.bottom, drawerContent > maximumDrawer ? 16 : 0)
                    .opacity(drawerShown ? 1 : 0)
            }
            .scrollIndicators(drawerContent > maximumDrawer ? .automatic : .never)
            .scrollDisabled(drawerContent <= maximumDrawer)
            .frame(height: visibleDrawer, alignment: .top)
            .overlay(alignment: .bottom) {
                // Longer content scrolls; the fade says there is more below.
                if drawerContent > maximumDrawer {
                    LinearGradient(colors: [Palette.panel.opacity(0), Palette.panel], startPoint: .top, endPoint: .bottom)
                        .frame(height: 28).allowsHitTesting(false)
                }
            }
            .clipped()
            Rectangle().fill(Palette.hairline).frame(height: visibleDrawer > 0 ? 1 : 0)
            PanelBar(model: model, state: current, editorOpen: showEditor, workStarted: workStarted, width: panelWidth,
                     primaryAction: primaryAction, toggleEditor: { showEditor ? closeEditor() : typeInstead() },
                     openSettings: openSettings)
        }
        .frame(width: panelWidth)
        .background(Palette.panel, in: RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous).strokeBorder(Color.white.opacity(0.1), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous))
        .animation(motion, value: visibleDrawer)
        .animation(fade, value: current.kind)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .foregroundStyle(Palette.foreground).preferredColorScheme(.dark).tint(Palette.accent)
        .environment(\.panelMotion, animates)
        .onPreferenceChange(DrawerHeightKey.self) { value in
            if drawerShown && abs(value - drawerContent) > 0.5 { drawerContent = value }
        }
        .onAppear { lastReported = targetHeight; resize(NSSize(width: panelWidth, height: targetHeight)) }
        .onChange(of: targetHeight) { _, value in report(value) }
        .onChange(of: panelWidth) { _, _ in resize(NSSize(width: panelWidth, height: targetHeight)) }
        .onChange(of: drawerShown) { _, shown in if !shown { drawerContent = 0 } }
        .onChange(of: model.busy) { _, busy in if busy { editing = false; workStarted = Date() } }
        .onChange(of: model.reviewDraft) { _, _ in showEditor = true }   // shown, not focused: the user's app keeps the keyboard
        .onChange(of: attentionIdentity) { _, _ in attentionCollapsed = false }
        .onChange(of: model.answerText) { _, _ in showDetails = false }
        .onExitCommand { closeEditor() }
    }
}

// MARK: Bar

private struct PanelBar: View {
    @ObservedObject var model: AppModel
    let state: PanelState
    let editorOpen: Bool
    let workStarted: Date
    let width: CGFloat
    let primaryAction: () -> Void
    let toggleEditor: () -> Void
    let openSettings: () -> Void
    private var stage: CGSize { CommandBarView.stageSize(for: width) }
    private var column: CGFloat { CommandBarView.columnWidth(for: width) }

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            if stage.width > 0 {
                ConductorStage(state: state.pose, tone: state.tone).frame(width: stage.width, height: stage.height)
            }
            VStack(alignment: .leading, spacing: 4) {
                eyebrow.frame(height: 16)
                line
            }
            .frame(width: column, height: 96, alignment: .topLeading)
            .padding(.top, 8)
            primaryButton
        }
        .padding(.leading, stage.width > 0 ? 12 : 16).padding(.trailing, 16)
        .frame(width: width, height: CommandBarView.barHeight, alignment: .leading)
        .overlay(alignment: .topTrailing) { secondaryControls.padding(.top, 8).padding(.trailing, 10) }
    }

    private var eyebrow: some View {
        HStack(spacing: 6) {
            if let icon = state.eyebrowIcon { Image(systemName: icon).font(.system(size: 10, weight: .bold)) }
            Text(LocalizedStringKey(state.eyebrow)).font(.system(size: 12, weight: .semibold)).layoutPriority(1)
            if state.meter { LevelMeter(level: model.level, color: state.tone) }
            if state.timer {
                Text(verbatim: "·").foregroundStyle(Palette.tertiary)
                TimelineView(.periodic(from: workStarted, by: 1)) { context in
                    Text(verbatim: Self.clock(context.date.timeIntervalSince(workStarted)))
                }.font(.system(size: 12).monospacedDigit()).foregroundStyle(Palette.tertiary)
            } else if let meta = state.meta {
                Text(verbatim: "·").foregroundStyle(Palette.tertiary)
                Text(LocalizedStringKey(meta)).font(.system(size: 12)).foregroundStyle(Palette.tertiary)
            }
        }
        .foregroundStyle(state.tone).lineLimit(1)
        .frame(maxWidth: column - 8, alignment: .leading)
    }
    static func clock(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    @ViewBuilder private var line: some View {
        if let words = state.words {
            let overflow = state.tail && PanelText.height(words, size: 15, spacing: 2, width: column) > 61
            Text(words)
                .font(.system(size: 15)).lineSpacing(2)
                .foregroundStyle(state.wordsProminent ? Palette.foreground : Palette.muted)
                .lineLimit(overflow ? nil : 3).truncationMode(.tail)
                .fixedSize(horizontal: false, vertical: overflow)
                .frame(width: column, height: 60, alignment: overflow ? .bottomLeading : .topLeading)
                .clipped()
                .mask(LinearGradient(stops: [.init(color: overflow ? .clear : .black, location: 0),
                                             .init(color: .black, location: overflow ? 0.42 : 0), .init(color: .black, location: 1)],
                                     startPoint: .top, endPoint: .bottom))
                .modifier(Shimmer(active: state.shimmer))
        } else if let hint = state.hint {
            VStack(alignment: .leading, spacing: 8) {
                Text(LocalizedStringKey(hint)).font(.system(size: 15)).foregroundStyle(Palette.tertiary).lineLimit(2)
                    .modifier(Shimmer(active: state.shimmer))
                if state.settingsLink {
                    Button("Open Settings", action: openSettings).buttonStyle(.plain)
                        .font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.accent)
                }
            }.frame(width: column, height: 60, alignment: .topLeading)
        }
    }

    private var primaryButton: some View {
        Button(action: primaryAction) {
            ZStack {
                Circle().fill(primaryFill)
                if state.primary == .micOn { Circle().strokeBorder(Palette.listening.opacity(0.85), lineWidth: 1.5) }
                switch state.primary {
                case .mic: Image(systemName: "mic.fill").font(.system(size: 16, weight: .semibold)).foregroundStyle(Palette.panel)
                case .micOn: Image(systemName: "mic.fill").font(.system(size: 16, weight: .semibold)).foregroundStyle(Palette.listening)
                case .live: LevelMeter(level: model.level, color: Palette.panel, bars: 5, height: 16, barWidth: 2.5)
                case .stop: RoundedRectangle(cornerRadius: 2.5, style: .continuous).fill(Palette.foreground).frame(width: 12, height: 12)
                case .wait: Spinner(color: Palette.recognizing)
                }
            }
            .frame(width: 40, height: 40).contentShape(Circle())
        }
        .buttonStyle(PressScale())
        .disabled(state.primary == .wait)
        .accessibilityLabel(primaryLabel)
        .help(state.primary == .stop ? "Stop this task and clear queued requests" : "Click to toggle listening. Hold Fn or right Option to speak, or press Option-Space.")
    }
    private var primaryFill: Color {
        switch state.primary {
        case .mic: return Palette.accent
        case .live: return Palette.listening
        case .micOn, .stop, .wait: return Palette.control
        }
    }
    private var primaryLabel: LocalizedStringKey {
        switch state.primary {
        case .mic: return "Turn mic on"
        case .micOn, .live: return "Turn mic off"
        case .stop: return "Stop task"
        case .wait: return "Recognizing"
        }
    }

    private var secondaryControls: some View {
        HStack(spacing: 0) {
            Button(action: toggleEditor) {
                Image(systemName: "keyboard").font(.system(size: 13)).frame(width: 26, height: 24).contentShape(Rectangle())
            }.buttonStyle(.plain).foregroundStyle(editorOpen ? Palette.accent : Palette.tertiary)
                .accessibilityLabel("Type a request").help("Type a request")
            Menu {
                Text(model.brainEnabled ? model.brainChoice.name : "No brain")
                Divider()
                ForEach(BrainChoice.all) { choice in
                    Button((choice.id == model.brainModel ? "✓ " : "    ") + choice.name + "  ·  " + choice.short) { model.selectBrain(choice, by: "bar") }
                        .disabled(choice.codex && CodexBrain.binary() == nil)
                }
                Divider()
                Button("Start new conversation") { model.newConversation() }
                if model.agentDashboardAvailable { Button("Agent dashboard") { model.openAgentMap() } }
                Button("Settings…", action: openSettings)
            } label: {
                Image(systemName: "ellipsis").font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(model.agentsOK ? Palette.tertiary : Palette.danger)
                    .frame(width: 26, height: 24).contentShape(Rectangle())
            }
            .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
            .accessibilityLabel("Brain model and settings")
            .help(model.agentsOK ? (model.brainEnabled ? model.brainChoice.name : "No brain") : model.agentsSummary)
        }
    }
}

// MARK: Drawer

private struct PanelDrawer: View {
    @ObservedObject var model: AppModel
    let state: PanelState
    let showsEditor: Bool
    @Binding var showDetails: Bool
    var editing: FocusState<Bool>.Binding
    let width: CGFloat
    var openSettings: () -> Void = {}
    var closeEditor: () -> Void = {}
    var typeInstead: () -> Void = {}
    var submit: () -> Void = {}
    var dismissNotice: () -> Void = {}
    var closeAnswer: () -> Void = {}
    var stop: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let notice = state.notice { section { noticeView(notice) } }
            if state.work {
                if state.notice != nil { separator }
                section { workView }
            }
            if state.answer {
                if state.notice != nil || state.work { separator }
                section { answerView }
            }
            if showsEditor {
                if state.notice != nil || state.work || state.answer { separator }
                section { editorView }
            }
        }
        .frame(width: width, alignment: .leading)
    }

    private var separator: some View { Rectangle().fill(Palette.hairline).frame(height: 1) }
    private func section<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content().padding(.horizontal, 16).padding(.vertical, 14).frame(maxWidth: .infinity, alignment: .leading)
    }
    private func closeButton(_ label: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "xmark").font(.system(size: 9, weight: .bold)).foregroundStyle(Palette.tertiary)
                .frame(width: 22, height: 22).background(Color.white.opacity(0.07), in: Circle()).contentShape(Circle())
        }.buttonStyle(.plain).accessibilityLabel(label)
    }

    // Attention: one title, one explanation, one useful action.
    @ViewBuilder private func noticeView(_ notice: PanelState.Notice) -> some View {
        let title: LocalizedStringKey? = {
            switch notice {
            case .setup: return "Finish setup"
            case .microphoneRequest: return "Allow microphone access"
            case .microphoneUnavailable: return "Microphone unavailable"
            case .reconnecting: return "Reconnecting the microphone"
            case .billing: return "Jev billing problem"
            case .general: return nil
            }
        }()
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                if let title { Text(title).font(.system(size: 15, weight: .semibold)) }
                Group {
                    switch notice {
                    case .setup: Text(LocalizedStringKey(PanelState.setupMessage(model)))
                    case .billing: Text(model.billingIssue ?? "")
                    case .microphoneUnavailable: Text(Self.dropping("Microphone unavailable.", from: model.detail))
                    default: Text(model.detail)
                    }
                }
                .font(.system(size: title == nil ? 15 : 13)).lineSpacing(title == nil ? 3 : 2)
                .foregroundStyle(title == nil ? Palette.foreground : Palette.muted)
                .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                switch notice {
                case .setup, .billing:
                    Button("Open Settings", action: openSettings).buttonStyle(ConductorButtonStyle(prominent: true)).padding(.top, 6)
                case .microphoneUnavailable:
                    Button("Type instead", action: typeInstead).buttonStyle(ConductorButtonStyle()).padding(.top, 6)
                default: EmptyView()
                }
            }
            Spacer(minLength: 0)
            closeButton("Dismiss attention message", action: dismissNotice)
        }
    }
    static func dropping(_ prefix: String, from text: String) -> String {
        guard text.hasPrefix(prefix) else { return text }
        return String(text.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
    }

    // Work: what is happening now, in Conductor's words.
    private var workView: some View {
        let detail = model.detail.trimmingCharacters(in: .whitespacesAndNewlines)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Group {
                    if detail.isEmpty { Text(model.phase == "Thinking" ? "Thinking" : "Acting") }
                    else { Text(detail) }
                }
                .font(.system(size: 15)).lineSpacing(3).foregroundStyle(Palette.foreground)
                .fixedSize(horizontal: false, vertical: true)
                .modifier(Shimmer(active: state.kind == .work && state.pose != .acting))
                Spacer(minLength: 0)
                if state.kind == .capture {
                    Button(action: stop) {
                        HStack(spacing: 5) {
                            RoundedRectangle(cornerRadius: 1.5).frame(width: 7, height: 7)
                            Text("Stop").font(.system(size: 12, weight: .medium))
                        }.padding(.horizontal, 10).frame(height: 24).background(Palette.control, in: Capsule())
                    }.buttonStyle(.plain).foregroundStyle(Palette.foreground).fixedSize()
                        .accessibilityLabel("Stop task").help("Stop this task and clear queued requests")
                }
            }
            if model.queuedCount > 0 || model.shotsThisCommand > 0 {
                HStack(spacing: 14) {
                    if model.queuedCount > 0 {
                        Label("\(model.queuedCount) queued", systemImage: "text.line.first.and.arrowtriangle.forward")
                            .accessibilityLabel("Queued requests: \(model.queuedCount)")
                    }
                    if model.shotsThisCommand > 0 {
                        Label("\(model.shotsThisCommand) screenshots", systemImage: "camera").help("Screenshots sent to the brain for this command")
                    }
                }.font(.system(size: 12)).foregroundStyle(Palette.tertiary).labelStyle(.titleAndIcon)
            }
        }
    }

    // Answer: the reply once, then who answered and the optional details.
    private var answerView: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                if state.errorAnswer {
                    let rest = Self.dropping(PanelState.failurePrefix, from: model.answerText)
                    VStack(alignment: .leading, spacing: 6) {
                        if rest != model.answerText {
                            Text("Couldn't complete the request").font(.system(size: 15, weight: .semibold))
                            Text(rest).font(.system(size: 13)).lineSpacing(2).foregroundStyle(Palette.muted)
                        } else {
                            Text(model.answerText).font(.system(size: 15)).lineSpacing(3)
                        }
                    }.fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                } else {
                    Text(model.answerText).font(.system(size: 15)).lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                }
                Spacer(minLength: 0)
                closeButton("Close answer", action: closeAnswer)
            }
            if !state.errorAnswer {
                HStack(spacing: 8) {
                    if !model.modelLabel.isEmpty {
                        Text(model.modelLabel).lineLimit(1)
                            .foregroundStyle(model.modelLabel.contains("fallback") ? Palette.danger : Palette.tertiary)
                    }
                    Spacer(minLength: 0)
                    Button { showDetails.toggle() } label: {
                        HStack(spacing: 4) {
                            Text("Details")
                            Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold)).rotationEffect(.degrees(showDetails ? 180 : 0))
                        }.contentShape(Rectangle())
                    }.buttonStyle(.plain).foregroundStyle(Palette.tertiary).fixedSize()
                }.font(.system(size: 12))
                if showDetails { details }
            }
        }
    }
    private var details: some View {
        VStack(alignment: .leading, spacing: 12) {
            Rectangle().fill(Palette.hairline).frame(height: 1)
            if !model.usageLine.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(Array((model.usageLine.components(separatedBy: " · ") + [model.dayLine]).filter { !$0.isEmpty }.enumerated()), id: \.offset) { _, line in
                        Text(line)
                    }
                }.font(.system(size: 12)).foregroundStyle(Palette.muted).textSelection(.enabled)
            }
            if model.limitShare != nil { LimitShareView(model: model) }
            if model.shotsThisCommand > 0, let shot = model.lastScreenshot {
                HStack(spacing: 12) {
                    Image(nsImage: shot).resizable().scaledToFit().frame(width: 80, height: 52)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Palette.hairline))
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Screenshots sent to the brain: \(model.shotsThisCommand)")
                        Text("\(model.shotsToday) today · the latest is at left").foregroundStyle(Palette.tertiary)
                    }.font(.system(size: 12))
                }
            }
            ContextBar(model: model)
        }
    }

    // Typing: one field that grows with the text, next to the bar.
    private var editorView: some View {
        let empty = model.typedCommand.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(model.busy ? "Add a request to the queue" : "Type a request").font(.system(size: 12, weight: .medium)).foregroundStyle(Palette.tertiary)
                Spacer()
                closeButton("Close typed input", action: closeEditor)
            }
            HStack(alignment: .bottom, spacing: 10) {
                TextField("", text: $model.typedCommand, prompt: Text("What would you like to do?").foregroundStyle(Palette.tertiary), axis: .vertical)
                    .textFieldStyle(.plain).font(.system(size: 15)).lineSpacing(2).lineLimit(1...6)
                    .focused(editing).onSubmit(submit)
                    .accessibilityLabel("Command transcript")
                    .padding(.vertical, 3)
                Button(action: submit) {
                    Image(systemName: "arrow.up").font(.system(size: 13, weight: .bold)).foregroundStyle(Palette.panel)
                        .frame(width: 26, height: 26).background(empty ? Palette.tertiary.opacity(0.6) : Palette.accent, in: Circle())
                }
                .buttonStyle(.plain).disabled(empty)
                .accessibilityLabel("Run command").help("Run command · Return")
            }
            .padding(.leading, 12).padding(.trailing, 6).padding(.vertical, 6)
            .background(Palette.field, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(editing.wrappedValue ? Palette.accent.opacity(0.7) : Palette.hairline))
        }
    }
}

/// Owns the focus state the drawer needs, so it can be measured outside the live panel.
private struct DrawerMeasure: View {
    @ObservedObject var model: AppModel
    let state: PanelState
    let typing: Bool
    let details: Bool
    let width: CGFloat
    @FocusState private var editing: Bool
    var body: some View {
        PanelDrawer(model: model, state: state, showsEditor: typing, showDetails: .constant(details), editing: $editing, width: width)
            .fixedSize(horizontal: false, vertical: true)
            .environment(\.panelMotion, false)
            .preferredColorScheme(.dark)
    }
}

// MARK: Pieces

/// The conductor in a fixed frame: whole, the same size in every pose, tinted by the state.
struct ConductorStage: View {
    let state: VoiceState
    let tone: Color
    @Environment(\.panelMotion) private var motion
    var body: some View {
        ZStack {
            Palette.matte
            ConductorStateView(state: state, animates: motion, framing: .stage)
            tone.opacity(state == .ready ? 0.06 : 0.1).allowsHitTesting(false)
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.white.opacity(0.06)))
        .animation(motion ? .easeInOut(duration: 0.3) : nil, value: tone)
    }
}

private struct LevelMeter: View {
    let level: Double
    let color: Color
    var bars = 4
    var height: CGFloat = 11
    var barWidth: CGFloat = 2
    @Environment(\.panelMotion) private var motion
    private static let profile: [Double] = [0.55, 1.0, 0.7, 0.9, 0.6]
    var body: some View {
        HStack(alignment: .center, spacing: barWidth) {
            ForEach(0..<bars, id: \.self) { index in
                Capsule().fill(color)
                    .frame(width: barWidth, height: max(barWidth + 1, height * min(1, max(0.18, level * 1.4)) * Self.profile[index % Self.profile.count]))
            }
        }
        .frame(height: height)
        .animation(motion ? .easeOut(duration: 0.08) : nil, value: level)
        .accessibilityHidden(true)
    }
}

private struct Spinner: View {
    let color: Color
    @State private var turning = false
    @Environment(\.panelMotion) private var motion
    var body: some View {
        Circle().trim(from: 0, to: 0.72)
            .stroke(color, style: StrokeStyle(lineWidth: 2, lineCap: .round))
            .frame(width: 16, height: 16)
            .rotationEffect(.degrees(turning ? 360 : 0))
            .animation(turning ? .linear(duration: 0.9).repeatForever(autoreverses: false) : nil, value: turning)
            .onAppear { turning = motion }
    }
}

/// A slow highlight across text while Conductor is still working on it.
private struct Shimmer: ViewModifier {
    let active: Bool
    @State private var phase: CGFloat = 0
    @Environment(\.panelMotion) private var motion
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func body(content: Content) -> some View {
        if active && motion && !reduceMotion {
            content
                .overlay {
                    GeometryReader { geometry in
                        LinearGradient(colors: [.clear, .white.opacity(0.5), .clear], startPoint: .leading, endPoint: .trailing)
                            .frame(width: geometry.size.width * 0.5)
                            .offset(x: -geometry.size.width * 0.5 + phase * geometry.size.width * 1.5)
                    }
                    .mask(content)
                    .allowsHitTesting(false)
                }
                .onAppear { withAnimation(.linear(duration: 1.8).repeatForever(autoreverses: false)) { phase = 1 } }
        } else {
            content
        }
    }
}

struct PressScale: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.93 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

enum PanelText {
    static func height(_ text: String, size: CGFloat, spacing: CGFloat, width: CGFloat) -> CGFloat {
        let paragraph = NSMutableParagraphStyle(); paragraph.lineSpacing = spacing
        let attributed = NSAttributedString(string: text, attributes: [.font: NSFont.systemFont(ofSize: size), .paragraphStyle: paragraph])
        return ceil(attributed.boundingRect(with: NSSize(width: width, height: .greatestFiniteMagnitude),
                                            options: [.usesLineFragmentOrigin, .usesFontLeading]).height)
    }
}
