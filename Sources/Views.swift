import AppKit
import SwiftUI

/// Shared, opaque surfaces for the native command panel and preferences.
enum Palette {
    static let background = Color(red: 16/255, green: 17/255, blue: 19/255)
    static let panel = Color(red: 23/255, green: 25/255, blue: 29/255)
    static let raised = Color(red: 35/255, green: 38/255, blue: 43/255)
    static let line = Color(red: 55/255, green: 59/255, blue: 66/255)
    static let accent = Color(red: 1, green: 195/255, blue: 74/255)
    static let foreground = Color(red: 245/255, green: 241/255, blue: 232/255)
    static let muted = Color(red: 202/255, green: 204/255, blue: 208/255)
    static let danger = Color(red: 1, green: 121/255, blue: 117/255)
    static let success = Color(red: 151/255, green: 198/255, blue: 159/255)
}

struct ConductorButtonStyle: ButtonStyle {
    var prominent = false
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(enabled && prominent ? Palette.panel : enabled ? Palette.foreground : Palette.muted)
            .padding(.horizontal, 13).padding(.vertical, 9)
            .background(enabled && prominent ? Palette.accent : Palette.raised, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(prominent && enabled ? Palette.accent : Palette.line))
            .opacity(enabled ? (configuration.isPressed ? 0.75 : 1) : 0.55)
    }
}

struct ConductorSwitchRow: View {
    let title: LocalizedStringKey
    @Binding var isOn: Bool
    var body: some View {
        HStack(spacing: 18) {
            Text(title).font(.system(size: 12, weight: .medium))
            Spacer(minLength: 12)
            Toggle(title, isOn: $isOn).labelsHidden().toggleStyle(.switch).controlSize(.small)
                .tint(Palette.accent).environment(\.controlActiveState, .active)
        }
    }
}

struct ConductorProgress: View {
    @State private var rotating = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        ZStack {
            Circle().stroke(Palette.accent.opacity(0.2), lineWidth: 1.5)
            Circle().trim(from: 0, to: 0.28).stroke(Palette.accent, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                .rotationEffect(.degrees(rotating ? 360 : 0))
        }.frame(width: 15, height: 15)
            .animation(reduceMotion ? nil : .linear(duration: 0.9).repeatForever(autoreverses: false), value: rotating)
            .onAppear { rotating = true }
            .accessibilityLabel("Working")
    }
}

struct Card<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        content.padding(18).frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.panel, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Palette.line))
    }
}

/// Settings keep their original bindings. Navigation and guide progress are presentation only.
struct SettingsView: View {
    @ObservedObject var model: AppModel
    @AppStorage("claudeCLIPath") private var claudeCLIPath = ""
    @AppStorage("codexCLIPath") private var codexCLIPath = ""
    @AppStorage("whisperServerPath") private var whisperServerPath = ""
    @AppStorage("whisperModelPath") private var whisperModelPath = ""
    @AppStorage("instructionsFilePath") private var instructionsFilePath = ""
    @AppStorage("diagnosticsEnabled") private var diagnosticsEnabled = false
    @State private var section: String
    @State private var showGuide: Bool
    @State private var guideStep: Int

    init(model: AppModel, initialSection: String? = nil, initiallyShowsGuide: Bool? = nil, initialGuideStep: Int = 0) {
        self.model = model
        _section = State(initialValue: initialSection ?? (model.settingsTab == "Jev activity" ? "Jev activity" : "Voice"))
        _showGuide = State(initialValue: initiallyShowsGuide ?? (!model.keyConfigured || !model.microphoneGranted || !model.speechGranted || !model.accessibilityGranted))
        _guideStep = State(initialValue: min(3, max(0, initialGuideStep)))
    }
    private let sections: [(String, String)] = [("Voice", "mic"), ("Connections", "link"), ("Access", "hand.raised"), ("Advanced", "slider.horizontal.3"), ("Jev activity", "arrow.left.arrow.right")]
    private var sectionDescription: String {
        switch section {
        case "Connections": return "Choose a brain and connect Jev's actions."
        case "Access": return "Give Conductor the access your requests need."
        case "Advanced": return "Local tools, conversation and privacy."
        case "Jev activity": return "Inspect the actual requests and responses from this session."
        default: return "Choose how a conversation starts."
        }
    }
    var body: some View {
        Group {
            if showGuide { guide }
            else { preferences }
        }
        .frame(minWidth: 760, minHeight: 590)
        .background(Palette.panel).foregroundStyle(Palette.foreground)
        .preferredColorScheme(.dark).tint(Palette.accent)
        .buttonStyle(ConductorButtonStyle())
        .onChange(of: model.settingsTab) { _, value in
            if value == "Jev activity" { section = value; showGuide = false }
        }
    }
    private var preferences: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Conductor").font(.system(size: 17, weight: .semibold)).padding(.horizontal, 12).padding(.top, 14).padding(.bottom, 18)
                ForEach(sections, id: \.0) { item in
                    Button {
                        section = item.0
                        model.settingsTab = item.0 == "Jev activity" ? "Jev activity" : "General"
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: item.1).frame(width: 15)
                            Text(LocalizedStringKey(item.0))
                            Spacer(minLength: 0)
                        }.font(.system(size: 12, weight: section == item.0 ? .semibold : .regular))
                            .padding(.horizontal, 12).padding(.vertical, 11)
                            .foregroundStyle(section == item.0 ? Palette.accent : Palette.foreground)
                            .background(section == item.0 ? Palette.accent.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 8))
                    }.buttonStyle(.plain)
                }
                Spacer()
                Button { showGuide = true; guideStep = 0 } label: { Label("Setup guide", systemImage: "sparkle") }
                    .buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(Palette.muted).padding(12)
                Button { model.showCommandBar?() } label: { Label("Command bar", systemImage: "rectangle.bottomthird.inset.filled") }
                    .buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(Palette.muted).padding(12)
            }.padding(11).frame(width: 165).background(Palette.background)
            Rectangle().fill(Palette.line).frame(width: 1)
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 7) {
                        Text(LocalizedStringKey(section)).font(.system(size: 25, weight: .semibold))
                        Text(LocalizedStringKey(sectionDescription)).font(.system(size: 12)).foregroundStyle(Palette.muted)
                    }
                    if let issue = model.billingIssue {
                        Label(issue, systemImage: "exclamationmark.circle").font(.system(size: 12)).foregroundStyle(Palette.danger)
                    }
                    switch section {
                    case "Connections": brainCard; jevCard
                    case "Access": permissionsCard; privacyDisclosure
                    case "Advanced": pathsCard; localAgentsCard; conversationCard; privacyCard
                    case "Jev activity": JevActivityView(model: model)
                    default: voiceCard
                    }
                }.padding(30).frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
    private var privacyDisclosure: some View {
        DisclosureGroup("Full access and privacy") { privacyCard.padding(.top, 12) }
            .font(.system(size: 12)).foregroundStyle(Palette.muted)
    }
    @ViewBuilder private var localAgentsCard: some View {
        if model.agentDashboardAvailable || LocalIntegrations.configured(.agentStatus) {
            Card {
                VStack(alignment: .leading, spacing: 10) {
                    Label("Local agents", systemImage: "person.2").font(.system(size: 15, weight: .semibold))
                    if !model.agentsSummary.isEmpty { Text(model.agentsSummary).font(.system(size: 12)).foregroundStyle(model.agentsOK ? Palette.muted : Palette.danger).fixedSize(horizontal: false, vertical: true) }
                    HStack {
                        if model.agentDashboardAvailable { Button("Agent dashboard") { model.openAgentMap() }.buttonStyle(ConductorButtonStyle()) }
                        if LocalIntegrations.configured(.agentStatus) { Button("Refresh agent status") { model.refreshAgentStatus() }.buttonStyle(.plain).foregroundStyle(Palette.muted) }
                    }
                }
            }
        }
    }
    private var conversationCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                Text("Conversation").font(.system(size: 15, weight: .semibold))
                ContextBar(model: model)
                Text("Conversation turns: \(model.brainTurns)").font(.system(size: 12)).foregroundStyle(Palette.muted)
                if model.limitShare != nil { LimitShareView(model: model) }
                if !model.usageLine.isEmpty {
                    Text(model.usageLine + "\n" + model.dayLine).font(.system(size: 12)).foregroundStyle(Palette.muted).textSelection(.enabled)
                }
                Button("Start new conversation") { model.newConversation() }
            }
        }
    }
    private var guide: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Welcome to Conductor").font(.system(size: 15, weight: .semibold))
                Spacer()
                Button("Preferences") { showGuide = false }.buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(Palette.muted)
            }.padding(.horizontal, 30).padding(.vertical, 19).background(Palette.raised.opacity(0.6))
            Rectangle().fill(Palette.line).frame(height: 1)
            ScrollView {
                VStack(alignment: .leading, spacing: 25) {
                    HStack {
                        ForEach(Array(["Brain", "Connection", "Mac access", "Try it"].enumerated()), id: \.offset) { index, title in
                            HStack(spacing: 7) {
                                Text("\(index + 1)").font(.system(size: 10, weight: .semibold)).frame(width: 21, height: 21)
                                    .foregroundStyle(index == guideStep ? Palette.panel : Palette.muted)
                                    .background(index == guideStep ? Palette.accent : Palette.raised, in: Circle())
                                Text(LocalizedStringKey(title)).font(.system(size: 11)).foregroundStyle(index == guideStep ? Palette.foreground : Palette.muted)
                            }
                            if index < 3 { Spacer(minLength: 16) }
                        }
                    }.padding(.bottom, 4)
                    VStack(alignment: .leading, spacing: 9) {
                        Text(LocalizedStringKey(["Choose the brain behind Conductor.", "Connect Jev's actions.", "Let Conductor work on your Mac.", "Try a small request."][guideStep]))
                            .font(.system(size: 26, weight: .semibold))
                        Text(LocalizedStringKey(["Use the Claude Code or ChatGPT login you already have. You can change the brain later.", "Your Jev API key stays in macOS Keychain. Check the connection when you are ready.", "These controls open the real macOS permission prompts. You can finish this later in Preferences.", "Open the local practice window, then hold Fn and say ‘click Blue’. Its buttons and text field are safe to try."][guideStep]))
                            .font(.system(size: 13)).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
                    }
                    switch guideStep {
                    case 0:
                        VStack(spacing: 9) { ForEach(BrainChoice.all) { choice in brainRow(choice) } }
                        Text("Finding a CLI does not verify its sign-in. Sign in with Claude Code or Codex before your first request.")
                            .font(.system(size: 12)).foregroundStyle(Palette.muted)
                        DisclosureGroup("Set paths manually") { pathsCard.padding(.top, 10) }.font(.system(size: 12))
                    case 1: jevCard
                    case 2: permissionsCard
                    default:
                        Card {
                            HStack(spacing: 22) {
                                Image(systemName: "macwindow.on.rectangle").font(.system(size: 38, weight: .light))
                                    .foregroundStyle(Palette.muted).frame(width: 92, height: 92).accessibilityHidden(true)
                                VStack(alignment: .leading, spacing: 12) {
                                    Text("Hold Fn and speak").font(.system(size: 16, weight: .semibold))
                                    Text("Release to send. The practice window shows what actually changed.").font(.system(size: 12)).foregroundStyle(Palette.muted)
                                    Button("Open practice window") { model.openPractice?() }.buttonStyle(ConductorButtonStyle(prominent: true))
                                }
                            }
                        }
                        Text("The practice window is local. Voice requests use your configured brain and Jev connection.").font(.system(size: 12)).foregroundStyle(Palette.muted)
                    }
                }.padding(38).frame(maxWidth: .infinity, alignment: .leading)
            }
            Rectangle().fill(Palette.line).frame(height: 1)
            HStack {
                Button("Finish later") { showGuide = false }.buttonStyle(.plain).foregroundStyle(Palette.muted)
                Spacer()
                if guideStep > 0 { Button("Back") { guideStep -= 1 } }
                Button(guideStep == 3 ? "Show command bar" : "Continue") {
                    if guideStep == 3 { showGuide = false; model.showCommandBar?() }
                    else { guideStep += 1 }
                }.buttonStyle(ConductorButtonStyle(prominent: true))
            }.padding(.horizontal, 30).padding(.vertical, 18).background(Palette.raised.opacity(0.5))
        }
    }
    private var brainCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                Label("Brain", systemImage: "brain.head.profile").font(.system(size: 16, weight: .semibold))
                ConductorSwitchRow(title: "Plan before acting", isOn: $model.brainEnabled)
                Text("Choose a Claude Code or Codex CLI brain. Sign in through that CLI with your Claude or ChatGPT account first, then select the model here.")
                    .font(.system(size: 12)).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
                ForEach(BrainChoice.all) { choice in brainRow(choice) }

            }
        }
    }

    private func brainRow(_ choice: BrainChoice) -> some View {
        let selected = model.brainModel == choice.id
        let executableFound = choice.codex ? CodexBrain.binary() != nil : ClaudeBrain.binary() != nil
        return Button { model.selectBrain(choice, by: "settings") } label: {
            HStack(spacing: 12) {
                Image(systemName: selected ? "largecircle.fill.circle" : "circle").font(.system(size: 16)).foregroundStyle(selected ? Palette.accent : Palette.muted)
                VStack(alignment: .leading, spacing: 2) {
                    Text(choice.name).font(.system(size: 14, weight: .semibold))
                    Text(executableFound ? choice.short : "CLI not found. Set its path in Advanced, install it, then sign in.")
                        .font(.system(size: 11)).foregroundStyle(executableFound ? Palette.muted : .orange).fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
            }
            .padding(.horizontal, 12).padding(.vertical, 9)
            .contentShape(Rectangle())
            .background(selected ? Palette.accent.opacity(0.10) : Color.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(selected ? Palette.accent.opacity(0.6) : Palette.line))
        }.buttonStyle(.plain).disabled(!executableFound || !model.brainEnabled)
    }

    private var pathsCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                Label("CLI and local speech paths", systemImage: "terminal").font(.system(size: 16, weight: .semibold))
                Text("Leave a field blank to let Conductor search its usual install locations. Paths are saved in this Mac's app settings.")
                    .font(.system(size: 11)).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
                TextField("Claude Code executable path", text: $claudeCLIPath).textFieldStyle(.roundedBorder)
                TextField("Codex executable path", text: $codexCLIPath).textFieldStyle(.roundedBorder)
                TextField("Personal instructions file (optional)", text: $instructionsFilePath).textFieldStyle(.roundedBorder)
                Text("Local instructions are used when a new brain conversation starts.").font(.system(size: 11)).foregroundStyle(Palette.muted)
                Divider()
                ConductorSwitchRow(title: "Use local Whisper for final transcription", isOn: $model.whisperEnabled)
                    .disabled(!LocalWhisper.shared.installed)
                TextField("whisper-server executable path", text: $whisperServerPath).textFieldStyle(.roundedBorder)
                TextField("Whisper model file path", text: $whisperModelPath).textFieldStyle(.roundedBorder)
                Text(LocalWhisper.shared.installed ? "Whisper is ready. Audio is sent to the local server on this Mac." : "Install whisper.cpp and a model, then enter both paths to enable local Whisper. Apple Speech remains the fallback.")
                    .font(.system(size: 11)).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var voiceCard: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Listen when").font(.system(size: 13, weight: .semibold))
                Picker("Listen when", selection: $model.continuousListening) {
                    Text("I hold Fn").tag(false)
                    Text("Continuous").tag(true)
                }.pickerStyle(.segmented).labelsHidden().frame(width: 340, alignment: .leading)
                Text(model.continuousListening ? "Conductor keeps listening between commands. Say ‘stop listening’ to turn off the microphone." : "Hold Fn or right Option, then release to send. A short tap lets you speak until the next tap. Option-Space listens for one command.")
                    .font(.system(size: 12)).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
                if model.continuousListening {
                    Text("Send a continuous command").font(.system(size: 12, weight: .medium)).padding(.top, 7)
                    Picker("Send a continuous command", selection: $model.sendByWord) {
                        Text("After ‘end command’ or Fn").tag(true)
                        Text("After a pause").tag(false)
                    }.labelsHidden().font(.system(size: 12)).fixedSize().frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            Divider().overlay(Palette.line)
            VStack(alignment: .leading, spacing: 10) {
                Text("Speech language").font(.system(size: 13, weight: .semibold))
                Picker("Speech language", selection: $model.speechLanguage) {
                    Text("English").tag("en-US")
                    Text("Russian").tag("ru-RU")
                }.pickerStyle(.segmented).labelsHidden().frame(width: 340, alignment: .leading)
                Text(model.localSpeechAvailable ? "A new language takes effect next time the microphone starts." : "Apple Speech Recognition is not available. Enable Dictation in System Settings → Keyboard.")
                    .font(.system(size: 12)).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
            }
            Divider().overlay(Palette.line)
            VStack(alignment: .leading, spacing: 10) {
                ConductorSwitchRow(title: "Spoken answers", isOn: $model.voiceFeedback)
                Text("Answers are always available as text in the command surface.")
                    .font(.system(size: 12)).foregroundStyle(Palette.muted)
            }
            DisclosureGroup("Useful voice commands") { phrasesCard.padding(.top, 10) }
                .font(.system(size: 12)).foregroundStyle(Palette.muted)
        }
    }

    private var phrasesCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 7) {
                Label("Voice commands", systemImage: "text.bubble").font(.system(size: 16, weight: .semibold))
                Text("Say ‘cancel task’ or click Stop to interrupt a running task. Say ‘stop listening’ to turn off the microphone. Say ‘start over’ to clear the brain's conversation context.")
                    .font(.system(size: 12)).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var jevCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                Label("Jev action selector", systemImage: "key.fill").font(.system(size: 16, weight: .semibold))
                Text(model.keyConfigured ? "Your Jev API key is stored in macOS Keychain." : "Add a TypeSafe or OpenRouter API key. Conductor stores it only in macOS Keychain.")
                    .font(.system(size: 12)).foregroundStyle(Palette.muted)
                if model.keyConfigured {
                    DisclosureGroup("Replace API key") { keyEntry.padding(.top, 8) }.font(.system(size: 12))
                } else { keyEntry }
                Text("Model: \(model.provider.model) via \(model.provider.name)").font(.system(size: 11, design: .monospaced)).foregroundStyle(Palette.accent)
                HStack {
                    Spacer()
                    Button(model.checkingConnection ? "Checking…" : "Check connection") { model.checkConnection() }
                        .disabled(!model.keyConfigured || model.busy || model.checkingConnection)
                }.font(.system(size: 11))
                if !model.connectionDetail.isEmpty { Text(model.connectionDetail).font(.system(size: 12)).fixedSize(horizontal: false, vertical: true) }
            }
        }
    }

    private var permissionsCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 13) {
                Label("macOS permissions", systemImage: "hand.raised.fill").font(.system(size: 16, weight: .semibold))
                permissionRow("Microphone and Speech Recognition", description: "Captures and transcribes voice commands.", enabled: model.microphoneGranted && model.speechGranted) { model.requestAudio() }
                Divider()
                permissionRow("Accessibility", description: "Reads available controls and performs UI actions.", enabled: model.accessibilityGranted) { model.requestAccessibility() }
                Divider()
                permissionRow("Screen Recording", description: "Lets the brain inspect a screenshot when a visual request needs it.", enabled: model.screenCaptureGranted) { model.requestScreenCapture() }
                Text("macOS may also prompt for Automation access when Conductor first controls an app. Grant access in System Settings to enable that app.")
                    .font(.system(size: 11)).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var privacyCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 9) {
                Text("Full access and privacy").font(.system(size: 14, weight: .medium))
                Text("The selected Claude Code or Codex CLI runs with its approval and sandbox checks bypassed. It can run commands, read and write files, use AppleScript and JXA, control apps, and use keyboard and pointer actions without asking you to approve each step in Conductor. Stop it with the Stop button or say ‘cancel task’. macOS privacy grants still apply and cannot be bypassed by the app.")
                    .font(.system(size: 12)).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
                Text("Apple Speech may use Apple's network service when on-device recognition is unavailable; optional Whisper runs locally. The selected brain provider receives the request, screen text, and screenshots when needed. The selected Jev provider (TypeSafe or OpenRouter) receives your request, screen text, available choices, and action history, but no audio or screenshots. Secure accessibility fields are excluded, but the unrestricted CLI brain may read local files or other app data to carry out a request.")
                    .font(.system(size: 12)).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
                ConductorSwitchRow(title: "Write diagnostic logs (may include screen text and commands)", isOn: $diagnosticsEnabled)
            }
        }
    }

    private var keyEntry: some View {
        HStack {
            SecureField("TypeSafe or OpenRouter API key", text: $model.keyInput).textFieldStyle(.roundedBorder)
            Button("Save") { model.saveKey() }.disabled(model.keyInput.isEmpty)
        }
    }

    private func permissionRow(_ title: String, description: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 12, weight: .medium))
                Text(description).font(.system(size: 12)).foregroundStyle(Palette.muted)
            }
            Spacer()
            Button(enabled ? "Enabled" : "Open Settings", action: action).disabled(enabled)
        }
    }
}


extension VoiceState {
    var presentationLabel: LocalizedStringKey {
        switch self {
        case .ready: return "Ready"
        case .listening: return "Listening"
        case .recognizing: return "Recognizing"
        case .thinking: return "Thinking"
        case .acting: return "Acting"
        case .checking: return "Checking"
        case .attention: return "Attention"
        }
    }
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
    var color: Color {
        switch self {
        case .ready: return Palette.muted
        case .listening, .attention: return Palette.danger
        case .recognizing, .thinking, .acting, .checking: return Palette.accent
        }
    }
}

/// Screen constraints belong to window presentation, never to the task engine.
@MainActor final class CommandSurfaceLimits: ObservableObject {
    @Published var width: CGFloat = 600
    @Published var height: CGFloat = 520
}

struct CommandBarView: View {
    @ObservedObject var model: AppModel
    @ObservedObject private var limits: CommandSurfaceLimits
    @FocusState private var editing: Bool
    @State private var showEditor: Bool
    @State private var showDetails: Bool
    @State private var attentionCollapsed: Bool
    let openSettings: () -> Void
    let releaseKeyboard: () -> Void
    let resize: (NSSize) -> Void
    static let width: CGFloat = 380
    static let railHeight: CGFloat = 132

    init(model: AppModel, openSettings: @escaping () -> Void, releaseKeyboard: @escaping () -> Void,
         resize: @escaping (NSSize) -> Void = { _ in }, maximumHeight: CGFloat = 520,
         initiallyEditing: Bool = false, initiallyShowsDetails: Bool = false, limits: CommandSurfaceLimits? = nil,
         initiallyAttentionCollapsed: Bool = false) {
        self.model = model
        self.openSettings = openSettings
        self.releaseKeyboard = releaseKeyboard
        self.resize = resize
        let constraints = limits ?? CommandSurfaceLimits()
        if limits == nil { constraints.height = maximumHeight }
        self.limits = constraints
        _showEditor = State(initialValue: initiallyEditing)
        _showDetails = State(initialValue: initiallyShowsDetails)
        _attentionCollapsed = State(initialValue: initiallyAttentionCollapsed)
    }
    private static func isCapturing(_ model: AppModel) -> Bool {
        model.holdingToTalk || (model.listening && model.micEnabled)
    }
    private static func needsAttention(_ model: AppModel) -> Bool {
        model.requestingAudio || model.voiceState == .attention || model.detail.hasPrefix("Microphone unavailable") || model.billingIssue != nil || !model.keyConfigured || !model.accessibilityGranted
    }
    private static func setupMessage(_ model: AppModel) -> String {
        if !model.keyConfigured && !model.accessibilityGranted { return "Connect Jev and allow Mac access." }
        if !model.keyConfigured { return "Connect Jev in Settings." }
        return "Allow Mac access in Settings."
    }
    private static func captureInstruction(_ model: AppModel) -> String {
        if model.holdingToTalk { return model.busy ? "Release Fn to add to the queue" : "Release Fn to send" }
        if model.tapListening || model.wordMode { return "Say ‘end command’ or press Fn to send" }
        return model.continuousListening ? "Pause to send your next request" : "Pause when finished"
    }
    private static func workFallback(_ model: AppModel) -> String {
        model.phase == "Thinking" ? "Thinking" : "Acting"
    }
    private static func artworkWidth(for width: CGFloat) -> CGFloat {
        min(132, max(100, width - 212))
    }
    private static func answerFitsColumn(_ model: AppModel, details: Bool, attention: Bool, width: CGFloat) -> Bool {
        guard !details, !attention, model.answerText.count <= 180 else { return false }
        let column = width < 320 ? width - 32 : width - Self.artworkWidth(for: width) - 36
        let paragraph = NSMutableParagraphStyle(); paragraph.lineSpacing = AnswerView.lineSpacing
        let text = NSAttributedString(string: model.answerText, attributes: [.font: AnswerView.textFont, .paragraphStyle: paragraph])
        return text.boundingRect(with: NSSize(width: max(100, column - 32), height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin, .usesFontLeading]).height <= 78
    }
    /// Content chooses the width. Only long content and typed input need a wider surface.
    private static func metrics(model: AppModel, typing: Bool, details: Bool, maximumHeight: CGFloat,
                                maximumWidth: CGFloat, attentionCollapsed: Bool) -> (size: NSSize, header: CGFloat, message: CGFloat) {
        let capturing = isCapturing(model)
        let recognizing = model.phase == "Recognizing"
        let attention = needsAttention(model) && !attentionCollapsed && !model.busy && !capturing && !recognizing
        let answer = !model.answerText.isEmpty && !model.busy && !capturing && !recognizing
        let extendedCapture = (capturing || recognizing) && (model.busy || model.liveTranscript.count > 120)
        let extendedWork = model.busy && model.detail.count > 180
        // State changes keep one width and one artwork size. Longer text grows
        // vertically; the explicit editor alone requests extra horizontal space.
        let targetWidth: CGFloat = typing ? 500 : Self.width
        let width = min(targetWidth, maximumWidth)
        let narrow = width < 320
        let columnWidth = max(120, width - (narrow ? 32 : Self.artworkWidth(for: width) + 36))
        let shortAnswer = answer && answerFitsColumn(model, details: details, attention: attention, width: width)
        let extendedAnswer = answer && !shortAnswer
        func textHeight(_ text: String, size: CGFloat, width: CGFloat? = nil, maximum: CGFloat = 500, weight: NSFont.Weight = .regular) -> CGFloat {
            guard !text.isEmpty else { return 0 }
            let paragraph = NSMutableParagraphStyle(); paragraph.lineSpacing = size == 17 ? AnswerView.lineSpacing : 3
            let attributed = NSAttributedString(string: text, attributes: [.font: NSFont.systemFont(ofSize: size, weight: weight), .paragraphStyle: paragraph])
            let measured = ceil(attributed.boundingRect(with: NSSize(width: width ?? columnWidth, height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin, .usesFontLeading]).height) + 3
            return min(maximum, measured)
        }
        func localized(_ key: String) -> String { NSLocalizedString(key, comment: "Command surface sizing") }
        var message: CGFloat = 0
        if attention {
            let setup = !model.keyConfigured || !model.accessibilityGranted
            message = 24 + 8 + textHeight(setup ? localized(setupMessage(model)) : model.detail, size: 12, maximum: 120)
        } else if shortAnswer {
            message = max(24, textHeight(model.answerText, size: 17, width: max(100, columnWidth - 32))) + 8 + 18
        } else if extendedAnswer {
            message = max(42, textHeight(model.transcript.isEmpty ? localized("Answer") : model.transcript, size: 14, width: max(100, columnWidth - 32), maximum: 48, weight: .medium))
        } else if model.busy || capturing || recognizing {
            if model.busy {
                if capturing { message += 15 + 7 }
                if !model.transcript.isEmpty { message += textHeight(model.transcript, size: 13, maximum: 40) + 7 }
                let detail = model.detail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? localized(workFallback(model)) : extendedWork ? model.phase : model.detail
                message += textHeight(detail, size: 17, maximum: 85, weight: .semibold)
            }
            if (capturing || recognizing) && !model.busy {
                if !model.liveTranscript.isEmpty && !extendedCapture {
                    message += 15 + 6 + textHeight(model.liveTranscript, size: 17, maximum: 110, weight: .semibold)
                } else { message += 22 }
                message += 8 + textHeight(localized(recognizing ? "One moment…" : captureInstruction(model)), size: 13, maximum: 42)
            }
        } else { message = 22 + 6 + 30 }
        let hasStats = model.queuedCount > 0 || (model.busy && model.shotsThisCommand > 0)
        let agentRow: CGFloat = 0
        let controlHeight: CGFloat = extendedAnswer ? (attention ? 34 : 0) : 34 + agentRow
        let controlsSpacing: CGFloat = controlHeight > 0 ? 12 : 0
        let statsHeight: CGFloat = hasStats ? 24 : 0
        let naturalHeader = max(extendedAnswer ? 114 : Self.railHeight, message + controlsSpacing + controlHeight + 28 + statsHeight) + (narrow ? 110 : 0)
        let hasExtension = extendedAnswer || extendedCapture || extendedWork
        let editorHeight: CGFloat = typing ? 106 : 0
        let footerHeight: CGFloat = extendedAnswer ? 54 : 0
        let header = min(naturalHeader, max(110, maximumHeight - editorHeight - footerHeight - (hasExtension ? 100 : 0)))
        let messageHeight = min(message, max(24, header - (narrow ? 110 : 0) - 28 - controlsSpacing - controlHeight - statsHeight))
        var extensionHeight: CGFloat = 0
        if extendedAnswer {
            extensionHeight += 28 + textHeight(model.answerText, size: 17, width: max(120, width - 40), maximum: 300)
            if attention { extensionHeight += 40 + (model.transcript.isEmpty ? 0 : 7 + textHeight(model.transcript, size: 12, width: max(120, width - 40), maximum: 36)) }
            if details {
                extensionHeight += 80
                if model.limitShare != nil { extensionHeight += 132 }
                if !model.usageLine.isEmpty { extensionHeight += textHeight(model.usageLine + "\n" + model.dayLine, size: 12, width: max(120, width - 40), maximum: 110) }
                if model.shotsThisCommand > 0 { extensionHeight += 68 }
            }
        }
        if extendedCapture {
            let transcript = model.liveTranscript.isEmpty ? localized(recognizing ? "One moment…" : "Go ahead, I'm listening.") : model.liveTranscript
            extensionHeight += 28 + textHeight(transcript, size: 18, width: max(120, width - 40), maximum: 260, weight: .semibold)
            if model.busy { extensionHeight += 15 + 8 + 8 + textHeight(localized(recognizing ? "Finishing your transcript" : captureInstruction(model)), size: 11, width: max(120, width - 40), maximum: 34) }
        }
        if extendedWork { extensionHeight += 28 + textHeight(model.detail, size: 17, width: max(120, width - 40), maximum: 260, weight: .semibold) }
        return (NSSize(width: width, height: min(maximumHeight, header + extensionHeight + footerHeight + editorHeight)), header, messageHeight)
    }
    static func preferredSize(model: AppModel, typing: Bool = false, details: Bool = false,
                              maximumHeight: CGFloat = 520, maximumWidth: CGFloat = 600, attentionCollapsed: Bool = false) -> NSSize {
        metrics(model: model, typing: typing, details: details, maximumHeight: maximumHeight,
                maximumWidth: maximumWidth, attentionCollapsed: attentionCollapsed).size
    }
    private var capturing: Bool { Self.isCapturing(model) }
    private var recognizing: Bool { model.phase == "Recognizing" }
    private var attention: Bool { Self.needsAttention(model) }
    private var showsAttention: Bool { attention && !attentionCollapsed }
    private var attentionVisible: Bool { showsAttention && !model.busy && !capturing && !recognizing }
    private var setupIncomplete: Bool { !model.keyConfigured || !model.accessibilityGranted }
    private var attentionIdentity: String { model.phase + "|" + model.detail + "|" + String(model.keyConfigured) + "|" + String(model.accessibilityGranted) + "|" + (model.billingIssue ?? "") }
    private var hasAnswer: Bool { !model.answerText.isEmpty && !model.busy && !capturing && !recognizing }
    private var extendedAnswer: Bool { hasAnswer && !Self.answerFitsColumn(model, details: showDetails, attention: attentionVisible, width: size.width) }
    private var extendedCapture: Bool { (capturing || recognizing) && (model.busy || model.liveTranscript.count > 120) }
    private var extendedWork: Bool { model.busy && model.detail.count > 180 }
    private var hasExtension: Bool { extendedAnswer || extendedCapture || extendedWork }
    private var layout: (size: NSSize, header: CGFloat, message: CGFloat) {
        Self.metrics(model: model, typing: showEditor, details: showDetails, maximumHeight: limits.height, maximumWidth: limits.width, attentionCollapsed: attentionCollapsed)
    }
    private var size: NSSize { layout.size }
    private var conductorState: VoiceState {
        attention && !model.busy && !capturing && !recognizing ? .attention : model.voiceState
    }
    private var microphoneHint: String {
        if model.requestingAudio { return "Allow microphone access" }
        if capturing { return Self.captureInstruction(model) }
        if recognizing { return "One moment…" }
        if setupIncomplete { return "Open Settings to finish setup." }
        if attention { return "Check Settings to continue." }
        if model.micEnabled { return "Mic on" }
        return "Hold Fn to speak"
    }
    private func typeInstead() {
        showEditor = true
        DispatchQueue.main.async { editing = true }
    }
    private func submit() {
        editing = false
        releaseKeyboard()
        model.runTyped()
        if model.typedCommand.isEmpty { showEditor = false }
    }
    var body: some View {
        VStack(spacing: 0) {
            composition.frame(height: layout.header)
            if hasExtension {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        if extendedWork { Text(model.detail).font(.system(size: 17, weight: .semibold)).textSelection(.enabled) }
                        if extendedCapture {
                            VStack(alignment: .leading, spacing: 8) {
                                if model.busy {
                                    Text(LocalizedStringKey(recognizing ? "Recognizing" : "Listening to your next request"))
                                        .font(.system(size: 11)).foregroundStyle(Palette.muted)
                                }
                                Group {
                                    if model.liveTranscript.isEmpty { Text(LocalizedStringKey(recognizing ? "One moment…" : "Go ahead, I'm listening.")) }
                                    else { Text(model.liveTranscript) }
                                }.font(.system(size: 18, weight: .semibold)).textSelection(.enabled)
                                if model.busy {
                                    Text(LocalizedStringKey(recognizing ? "Finishing your transcript" : Self.captureInstruction(model)))
                                        .font(.system(size: 11)).foregroundStyle(Palette.muted)
                                }
                            }
                        }
                        if extendedAnswer { AnswerView(model: model, showsDetails: $showDetails, showsHeader: attentionVisible, showsFooter: false) }
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 20).padding(.top, 6).padding(.bottom, 20)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            if extendedAnswer { answerFooter }
            if showEditor {
                editor.padding(.horizontal, 16).padding(.vertical, 13).frame(height: 106)
            }
        }
        .frame(width: size.width, height: size.height)
        .background(Palette.panel, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Palette.line, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .foregroundStyle(Palette.foreground).preferredColorScheme(.dark).tint(Palette.accent)
        .onAppear { resize(size) }
        .onChange(of: size) { _, value in resize(value) }
        .onChange(of: model.busy) { _, busy in if busy { editing = false } }
        .onChange(of: model.reviewDraft) { _, _ in showEditor = true }   // shown, not focused: the user's app keeps the keyboard
        .onChange(of: attentionIdentity) { _, _ in attentionCollapsed = false }
        .onExitCommand { editing = false; showEditor = false; releaseKeyboard() }
    }
    @ViewBuilder private var composition: some View {
        if size.width < 320 {
            VStack(spacing: 0) {
                ConductorStateView(state: conductorState).frame(width: 140, height: 103)
                primaryColumn.padding(.horizontal, 16)
            }
        } else {
            HStack(alignment: .bottom, spacing: 12) {
                ConductorStateView(state: conductorState).frame(width: Self.artworkWidth(for: size.width), height: Self.artworkWidth(for: size.width) * 264 / 360)
                    .frame(maxHeight: .infinity, alignment: .bottom)
                primaryColumn
            }.padding(.horizontal, 12)
        }
    }
    private var primaryColumn: some View {
        VStack(alignment: .leading, spacing: 12) {
            ScrollView {
                primaryContent.frame(maxWidth: .infinity, alignment: .leading)
            }.scrollIndicators(.hidden).frame(maxWidth: .infinity).frame(height: layout.message)
            if model.queuedCount > 0 || (model.busy && model.shotsThisCommand > 0) {
                HStack(spacing: 12) {
                    if model.queuedCount > 0 { Text("\(model.queuedCount) queued").accessibilityLabel("Queued requests: \(model.queuedCount)") }
                    if model.busy && model.shotsThisCommand > 0 {
                        Label("\(model.shotsThisCommand)", systemImage: "camera").help("Screenshots sent to the brain for this command")
                    }
                }.font(.system(size: 10)).foregroundStyle(Palette.muted)
            }
            if extendedAnswer {
                if attentionVisible { attentionAction }
            } else { controls() }
        }.padding(.vertical, 14).frame(maxWidth: .infinity, alignment: .leading).frame(maxHeight: .infinity, alignment: .center)
    }
    @ViewBuilder private var primaryContent: some View {
        if attentionVisible {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 8) {
                    Text(LocalizedStringKey(model.requestingAudio ? "Allow microphone access" : setupIncomplete ? "Finish setup" : "Needs attention"))
                        .font(.system(size: 17, weight: .semibold)).foregroundStyle(Palette.danger)
                    Spacer(minLength: 0)
                    Button { attentionCollapsed = true } label: { Image(systemName: "xmark").font(.system(size: 10, weight: .semibold)).frame(width: 24, height: 24) }
                        .buttonStyle(.plain).foregroundStyle(Palette.muted).accessibilityLabel("Dismiss attention message")
                }
                Group {
                    if setupIncomplete { Text(LocalizedStringKey(Self.setupMessage(model))) }
                    else { Text(model.detail) }
                }.font(.system(size: 12)).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
            }
        } else if hasAnswer {
            if !extendedAnswer {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .top, spacing: 8) {
                        Text(model.answerText).font(Font(AnswerView.textFont)).lineSpacing(AnswerView.lineSpacing).textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                        closeAnswer
                    }
                    answerMetadata
                }
            } else {
                HStack(alignment: .top, spacing: 8) {
                    Group {
                        if model.transcript.isEmpty { Text("Answer") }
                        else { Text(model.transcript) }
                    }.font(.system(size: 14, weight: .medium)).lineLimit(2)
                    Spacer(minLength: 0)
                    closeAnswer
                }
            }
        } else if model.busy || capturing || recognizing {
            VStack(alignment: .leading, spacing: 14) {
                if model.busy {
                    VStack(alignment: .leading, spacing: 7) {
                        if capturing {
                            HStack(spacing: 6) {
                                Circle().fill(Palette.danger).frame(width: 5, height: 5)
                                Text("Listening to your next request").font(.system(size: 11)).foregroundStyle(Palette.muted)
                            }
                        }
                        if !model.transcript.isEmpty { Text(model.transcript).font(.system(size: 13)).foregroundStyle(Palette.muted).lineLimit(2) }
                        Group {
                            if model.detail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { Text(LocalizedStringKey(Self.workFallback(model))) }
                            else { Text(extendedWork ? model.phase : model.detail) }
                        }.font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(Palette.foreground)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                if (capturing || recognizing) && !model.busy {
                    VStack(alignment: .leading, spacing: 8) {
                        if !model.liveTranscript.isEmpty && !extendedCapture {
                            Text(LocalizedStringKey(recognizing ? "Recognizing" : model.busy ? "Listening to your next request" : "Listening"))
                                .font(.system(size: 13)).foregroundStyle(Palette.muted)
                            Text(model.liveTranscript).font(.system(size: 17, weight: .semibold)).textSelection(.enabled)
                        } else {
                            Text(LocalizedStringKey(recognizing ? "Recognizing" : model.busy ? "Listening to your next request" : "Listening"))
                                .font(.system(size: 17, weight: .semibold))
                        }
                        Text(LocalizedStringKey(recognizing ? "One moment…" : Self.captureInstruction(model)))
                            .font(.system(size: 13)).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Text(conductorState.presentationLabel).font(.system(size: 17, weight: .semibold))
                Text(LocalizedStringKey(microphoneHint)).font(.system(size: 12)).foregroundStyle(Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
                if attentionCollapsed && attention {
                    Button("Open Settings", action: openSettings).buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(Palette.accent)
                }
            }
        }
    }
    private var closeAnswer: some View {
        Button { model.dismissAnswer() } label: { Image(systemName: "xmark").font(.system(size: 10, weight: .semibold)).frame(width: 24, height: 24) }
            .buttonStyle(.plain).foregroundStyle(Palette.muted).accessibilityLabel("Close answer")
    }
    private var answerMetadata: some View {
        HStack(spacing: 8) {
            if !model.modelLabel.isEmpty {
                Text(model.modelLabel).font(.system(size: 10, weight: .medium)).lineLimit(1)
                    .foregroundStyle(model.modelLabel.contains("fallback") ? Palette.danger : Palette.muted)
            }
            Spacer(minLength: 0)
            Button { showDetails.toggle() } label: {
                HStack(spacing: 5) { Text("Details"); Image(systemName: showDetails ? "chevron.up" : "chevron.down").font(.system(size: 8, weight: .semibold)) }
            }.buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(Palette.muted).fixedSize()
        }
    }
    private var answerFooter: some View {
        HStack(spacing: 16) {
            answerMetadata
            controls(includeAttentionAction: false).fixedSize(horizontal: true, vertical: false)
        }.padding(.horizontal, 20).frame(height: 54)
    }
    @ViewBuilder private var attentionAction: some View {
        if setupIncomplete {
            Button("Open Settings", action: openSettings).buttonStyle(ConductorButtonStyle(prominent: true))
        } else {
            Button("Type instead") { typeInstead() }.buttonStyle(ConductorButtonStyle())
        }
    }
    private var editor: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack {
                Text(model.busy ? "Add a request to the queue" : "Type a request").font(.system(size: 12, weight: .medium)).foregroundStyle(Palette.muted)
                Spacer()
                Button { editing = false; showEditor = false; releaseKeyboard() } label: { Image(systemName: "xmark").font(.system(size: 10, weight: .semibold)) }
                    .buttonStyle(.plain).foregroundStyle(Palette.muted).accessibilityLabel("Close typed input")
            }
            HStack(alignment: .center, spacing: 12) {
                TextField("What would you like to do?", text: $model.typedCommand)
                    .textFieldStyle(.plain).font(.system(size: 15)).focused($editing).onSubmit { submit() }
                    .accessibilityLabel("Command transcript")
                Button { submit() } label: { Image(systemName: "arrow.up").font(.system(size: 13, weight: .semibold)).frame(width: 30, height: 30) }
                    .buttonStyle(.plain).foregroundStyle(Palette.panel)
                    .background(model.typedCommand.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Palette.muted : Palette.accent, in: RoundedRectangle(cornerRadius: 8))
                    .disabled(model.typedCommand.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityLabel("Run command").help("Run command · Return")
            }.padding(12).background(Palette.background, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(editing ? Palette.accent : Palette.line))
        }
    }
    private func controls(includeAttentionAction: Bool = true) -> some View {
        HStack(spacing: size.width < 380 ? 6 : 8) {
            if attentionVisible && includeAttentionAction { attentionAction }
            Button {
                editing = false
                releaseKeyboard()
                model.toggleListening()
            } label: {
                Image(systemName: capturing ? "waveform" : model.micEnabled ? "mic.fill" : "mic")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(capturing || model.micEnabled ? Palette.danger : Palette.accent)
                    .opacity(capturing ? 0.6 + min(1, max(0, model.level)) * 0.4 : 1)
                    .frame(width: 34, height: 34)
                    .background(capturing || model.micEnabled ? Palette.danger.opacity(0.10) : Palette.raised, in: RoundedRectangle(cornerRadius: 9))
                    .contentShape(RoundedRectangle(cornerRadius: 9))
            }.buttonStyle(.plain).accessibilityLabel(model.micEnabled ? "Turn mic off" : "Turn mic on")
                .help("Click to toggle listening. Hold Fn or right Option to speak, or press Option-Space.")
            if !attentionVisible || !includeAttentionAction {
            Button { if showEditor { editing = false; showEditor = false; releaseKeyboard() } else { typeInstead() } } label: {
                Image(systemName: "keyboard").font(.system(size: 15)).frame(width: 27, height: 30)
            }.buttonStyle(.plain).foregroundStyle(showEditor ? Palette.accent : Palette.muted)
                .accessibilityLabel("Type a request").help("Type a request")
            }
            Menu {
                Text(model.brainEnabled ? model.brainChoice.name : "No brain")
                Divider()
                ForEach(BrainChoice.all) { choice in
                    Button((choice.id == model.brainModel ? "✓ " : "    ") + choice.name + "  ·  " + choice.short) { model.selectBrain(choice, by: "bar") }
                        .disabled(choice.codex && CodexBrain.binary() == nil)
                }
                Divider()
                Button("Type a request") { typeInstead() }
                Button("Start new conversation") { model.newConversation() }
                if model.agentDashboardAvailable { Button("Agent dashboard") { model.openAgentMap() } }
                Button("Settings…", action: openSettings)
            } label: { Image(systemName: "ellipsis").font(.system(size: 16, weight: .semibold)).frame(width: 27, height: 30) }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                .foregroundStyle(model.agentsOK ? Palette.muted : Palette.danger).accessibilityLabel("Brain model and settings")
                .help(model.brainEnabled ? model.brainChoice.name : "No brain")
            if model.busy {
                Spacer(minLength: 0)
                Button { model.cancelCurrentTask() } label: {
                    HStack(spacing: 6) { Image(systemName: "stop.fill").font(.system(size: 7)); Text("Stop").font(.system(size: 12)).fixedSize() }
                        .padding(.horizontal, 11).frame(height: 32).foregroundStyle(Palette.danger)
                        .background(Palette.danger.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Palette.danger.opacity(0.4)))
                }.buttonStyle(.plain).fixedSize(horizontal: true, vertical: false).accessibilityLabel("Stop task").help("Stop this task and clear queued requests")
            }
        }
    }
}

/// Inline answer content. Its data and dismissal remain owned by AppModel.
struct AnswerView: View {
    @ObservedObject var model: AppModel
    @Binding var showsDetails: Bool
    let showsHeader: Bool
    let showsFooter: Bool
    static let width: CGFloat = 600
    static let textFont = NSFont.systemFont(ofSize: 17)
    static let lineSpacing: CGFloat = 5
    static let horizontalPadding: CGFloat = 24
    init(model: AppModel, showsDetails: Binding<Bool> = .constant(false), showsHeader: Bool = true, showsFooter: Bool = true) {
        self.model = model; _showsDetails = showsDetails; self.showsHeader = showsHeader; self.showsFooter = showsFooter
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if showsHeader {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 7) {
                    Text("Answer").font(.system(size: 12, weight: .medium)).foregroundStyle(Palette.muted)
                    if !model.transcript.isEmpty { Text(model.transcript).font(.system(size: 12)).foregroundStyle(Palette.muted).lineLimit(2) }
                }
                Spacer()
                Button { model.dismissAnswer() } label: { Image(systemName: "xmark").font(.system(size: 11, weight: .semibold)).frame(width: 24, height: 24) }
                    .buttonStyle(.plain).foregroundStyle(Palette.muted).accessibilityLabel("Close answer")
            }
            }
            Text(model.answerText).font(Font(Self.textFont)).lineSpacing(Self.lineSpacing).textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading).fixedSize(horizontal: false, vertical: true)
            if showsFooter {
            HStack {
                if !model.modelLabel.isEmpty {
                    Label(model.modelLabel, systemImage: "brain.head.profile").font(.system(size: 11, weight: .medium))
                        .foregroundStyle(model.modelLabel.contains("fallback") ? Palette.danger : Palette.muted)
                }
                Spacer()
                Button { showsDetails.toggle() } label: {
                    HStack(spacing: 5) { Text("Details"); Image(systemName: showsDetails ? "chevron.up" : "chevron.down").font(.system(size: 8, weight: .semibold)) }
                }.buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(Palette.muted)
            }
            }
            if showsDetails {
                Divider().overlay(Palette.line)
                if model.limitShare != nil { LimitShareView(model: model) }
                if !model.usageLine.isEmpty {
                    Text(model.usageLine + "\n" + model.dayLine).font(.system(size: 12)).foregroundStyle(Palette.muted).textSelection(.enabled)
                }
                if model.shotsThisCommand > 0, let shot = model.lastScreenshot {
                    HStack(spacing: 12) {
                        Image(nsImage: shot).resizable().scaledToFit().frame(width: 80, height: 52)
                            .clipShape(RoundedRectangle(cornerRadius: 5)).overlay(RoundedRectangle(cornerRadius: 5).stroke(Palette.line))
                        VStack(alignment: .leading, spacing: 4) {
                            Label("Screenshots sent to the brain: \(model.shotsThisCommand)", systemImage: "camera.viewfinder")
                            Text("\(model.shotsToday) today · latest screenshot at left").foregroundStyle(Palette.muted)
                        }.font(.system(size: 11))
                    }
                }
                ContextBar(model: model)
            }
        }
    }
}

struct PracticeView: View {
    @ObservedObject var model: AppModel
    @State private var color = Palette.accent
    @State private var result = "Pick a color with your voice."
    @State private var text = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 9) {
                Text("Try a small request.").font(.system(size: 27, weight: .semibold))
                Text("Hold Fn and say ‘click Blue’, then release.\nHold Fn again to say ‘type hello world’. You can also click the microphone to listen for one command.").font(.system(size: 13)).foregroundStyle(Palette.muted)
            }
            RoundedRectangle(cornerRadius: 15).fill(color).frame(height: 100)
                .overlay(Text(result).font(.system(size: 18, weight: .medium)).foregroundStyle(Palette.background)).accessibilityLabel(result)
            HStack(spacing: 12) {
                Button { color = .cyan; result = "Blue selected" } label: { Text(verbatim: "Blue") }.accessibilityLabel(Text(verbatim: "Blue"))
                Button { color = .orange; result = "Coral selected" } label: { Text(verbatim: "Coral") }.accessibilityLabel(Text(verbatim: "Coral"))
                Button("Reset") { color = Palette.accent; result = "Pick a color with your voice."; text = "" }
            }.buttonStyle(ConductorButtonStyle())
            TextField("Practice text", text: $text).textFieldStyle(.roundedBorder).accessibilityLabel("Practice text")
            HStack {
                Button("Send message") { result = "Practice only: nothing was sent." }
                Text("A local practice action; nothing is sent externally.").font(.system(size: 11)).foregroundStyle(Palette.muted)
            }
            HStack {
                Button("Show command bar") { model.showCommandBar?() }
                Spacer()
                Text("No external side effects").font(.system(size: 10)).foregroundStyle(Palette.muted)
            }
        }.padding(30).frame(width: 475).background(Palette.panel).foregroundStyle(Palette.foreground).preferredColorScheme(.dark).tint(Palette.accent)
            .buttonStyle(ConductorButtonStyle())
    }
}

struct ContextBar: View {
    @ObservedObject var model: AppModel
    private var color: Color { model.contextFraction >= 0.85 ? Palette.danger : model.contextFraction >= 0.6 ? Palette.accent : Palette.success }
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if model.contextUsed > 0 {
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Palette.raised)
                        Capsule().fill(color).frame(width: max(4, geometry.size.width * model.contextFraction))
                    }
                }.frame(height: 5)
            }
            Text(model.contextLabel).font(.system(size: 12, weight: .medium)).foregroundStyle(model.contextFraction >= 0.85 ? color : Palette.muted)
        }
    }
}

struct LimitShareView: View {
    @ObservedObject var model: AppModel
    private func number(_ value: Double) -> String {
        String(format: value >= 10 ? "%.0f" : value >= 1 ? "%.1f" : value >= 0.1 ? "%.2f" : "%.3f", value)
    }
    private func summary(_ share: LocalIntegrations.LimitShare) -> String {
        var text = String(format: NSLocalizedString("All sessions: %@%%. Conductor: ≈%@%%.", comment: "Estimated usage"), number(share.fiveHour), number(share.jevPercent))
        if let resets = share.resets {
            let time = DateFormatter.localizedString(from: resets, dateStyle: .none, timeStyle: .short)
            text += " " + String(format: NSLocalizedString("Resets at %@.", comment: "Usage reset"), time)
        }
        if let week = share.week {
            text += " " + String(format: NSLocalizedString("Weekly usage: %@%%.", comment: "Weekly usage"), number(week))
        }
        return text
    }
    var body: some View {
        if let share = model.limitShare {
            VStack(alignment: .leading, spacing: 6) {
                Text(String(format: NSLocalizedString("This command: ≈%@%% of the five-hour limit", comment: "Estimated usage"), number(share.commandPercent)))
                    .font(.system(size: 12, weight: .semibold))
                GeometryReader { geometry in
                    let width = geometry.size.width
                    let used = min(1, share.fiveHour / 100), app = min(used, share.jevPercent / 100), command = min(app, share.commandPercent / 100)
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.08))
                        Capsule().fill(Color.white.opacity(0.28)).frame(width: width * used)
                        Capsule().fill(Palette.accent).frame(width: max(0, width * app))
                        Rectangle().fill(Color.white).frame(width: max(0, width * command)).offset(x: max(0, width * (app - command)))
                    }
                }.frame(height: 7)
                Text(summary(share))
                    .font(.system(size: 11)).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
                Text("Estimated from local session costs. Account use on other devices can affect this estimate.")
                    .font(.system(size: 10)).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
            }
        } else if !model.usageLine.isEmpty {
            Text(model.usageLine).font(.system(size: 12)).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
        }
    }
}
