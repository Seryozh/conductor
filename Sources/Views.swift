import AppKit
import SwiftUI

/// Shared, opaque surfaces for the native command panel and preferences.
enum Palette {
    static let background = Color(red: 16/255, green: 17/255, blue: 19/255)
    static let window = Color(red: 21/255, green: 22/255, blue: 25/255)
    static let panel = Color(red: 28/255, green: 29/255, blue: 33/255)
    static let raised = Color(red: 38/255, green: 40/255, blue: 45/255)
    static let control = Color(red: 46/255, green: 48/255, blue: 54/255)
    static let field = Color(red: 18/255, green: 19/255, blue: 22/255)
    /// The artwork's own background, so the conductor sits in its frame without a visible box.
    static let matte = Color(red: 22/255, green: 24/255, blue: 27/255)
    static let hairline = Color.white.opacity(0.08)
    static let accent = Color(red: 1, green: 195/255, blue: 74/255)
    static let foreground = Color(red: 245/255, green: 241/255, blue: 232/255)
    static let muted = Color(red: 202/255, green: 204/255, blue: 208/255)
    static let tertiary = Color(red: 142/255, green: 145/255, blue: 152/255)
    static let danger = Color(red: 1, green: 121/255, blue: 117/255)
    static let success = Color(red: 151/255, green: 198/255, blue: 159/255)
    static let listening = Color(red: 245/255, green: 158/255, blue: 76/255)
    static let recognizing = Color(red: 92/255, green: 184/255, blue: 240/255)
    static let thinking = Color(red: 166/255, green: 140/255, blue: 245/255)
}

/// Type scale for every surface: 22 page titles, 15 titles and answers, 13 body, 12 captions.
struct ConductorButtonStyle: ButtonStyle {
    var prominent = false
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(prominent ? Palette.panel : Palette.foreground)
            .padding(.horizontal, 12).frame(minHeight: 28)
            .background(prominent ? Palette.accent : Color.white.opacity(configuration.isPressed ? 0.15 : 0.09),
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .opacity(enabled ? (configuration.isPressed && prominent ? 0.8 : 1) : 0.45)
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

struct ConductorSwitchRow: View {
    let title: LocalizedStringKey
    @Binding var isOn: Bool
    var body: some View {
        HStack(spacing: 16) {
            Text(title).font(.system(size: 13))
            Spacer(minLength: 12)
            Toggle(title, isOn: $isOn).labelsHidden().toggleStyle(.switch).controlSize(.small)
                .tint(Palette.accent).environment(\.controlActiveState, .active)
        }
    }
}

/// One settings group: an optional title and its controls on a raised surface.
struct Card<Content: View>: View {
    var title: LocalizedStringKey? = nil
    var systemImage: String? = nil
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title {
                HStack(spacing: 8) {
                    if let systemImage { Image(systemName: systemImage).font(.system(size: 13)).foregroundStyle(Palette.tertiary) }
                    Text(title).font(.system(size: 15, weight: .semibold))
                }
            }
            content
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.panel, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Palette.hairline))
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
        .background(Palette.window).foregroundStyle(Palette.foreground)
        .preferredColorScheme(.dark).tint(Palette.accent)
        .buttonStyle(ConductorButtonStyle())
        .onChange(of: model.settingsTab) { _, value in
            if value == "Jev activity" { section = value; showGuide = false }
        }
    }
    private var preferences: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Conductor").font(.system(size: 15, weight: .semibold)).padding(.horizontal, 10).padding(.top, 16).padding(.bottom, 16)
                ForEach(sections, id: \.0) { item in
                    Button {
                        section = item.0
                        model.settingsTab = item.0 == "Jev activity" ? "Jev activity" : "General"
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: item.1).font(.system(size: 13)).frame(width: 16)
                            Text(LocalizedStringKey(item.0))
                            Spacer(minLength: 0)
                        }.font(.system(size: 13, weight: section == item.0 ? .semibold : .regular))
                            .padding(.horizontal, 10).frame(height: 32)
                            .foregroundStyle(section == item.0 ? Palette.accent : Palette.foreground)
                            .background(section == item.0 ? Palette.accent.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .contentShape(Rectangle())
                    }.buttonStyle(.plain)
                }
                Spacer()
                Button { showGuide = true; guideStep = 0 } label: { Label("Setup guide", systemImage: "sparkle") }
                    .buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(Palette.tertiary).padding(.horizontal, 10).padding(.vertical, 6)
                Button { model.showCommandBar?() } label: { Label("Command bar", systemImage: "rectangle.bottomthird.inset.filled") }
                    .buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(Palette.tertiary).padding(.horizontal, 10).padding(.vertical, 6)
            }.padding(12).frame(width: 180).background(Palette.background)
            Rectangle().fill(Palette.hairline).frame(width: 1)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(LocalizedStringKey(section)).font(.system(size: 22, weight: .semibold))
                        Text(LocalizedStringKey(sectionDescription)).font(.system(size: 13)).foregroundStyle(Palette.muted)
                    }.padding(.bottom, 8)
                    if let issue = model.billingIssue {
                        Label(issue, systemImage: "exclamationmark.circle.fill").font(.system(size: 13)).foregroundStyle(Palette.danger)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                            .background(Palette.danger.opacity(0.1), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    switch section {
                    case "Connections": brainCard; jevCard
                    case "Access": permissionsCard; privacyDisclosure
                    case "Advanced": cliCard; whisperCard; localAgentsCard; conversationCard; privacyCard
                    case "Jev activity": JevActivityView(model: model)
                    default: voiceCards
                    }
                }.padding(32).frame(maxWidth: 680, alignment: .leading).frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
    private func caption(_ text: LocalizedStringKey) -> some View {
        Text(text).font(.system(size: 12)).foregroundStyle(Palette.tertiary).fixedSize(horizontal: false, vertical: true)
    }
    private var privacyDisclosure: some View {
        DisclosureGroup("Full access and privacy") { privacyCard.padding(.top, 12) }
            .font(.system(size: 13)).foregroundStyle(Palette.muted)
    }
    @ViewBuilder private var localAgentsCard: some View {
        if model.agentDashboardAvailable || LocalIntegrations.configured(.agentStatus) {
            Card(title: "Local agents", systemImage: "person.2") {
                if !model.agentsSummary.isEmpty { Text(model.agentsSummary).font(.system(size: 13)).foregroundStyle(model.agentsOK ? Palette.muted : Palette.danger).fixedSize(horizontal: false, vertical: true) }
                HStack(spacing: 12) {
                    if model.agentDashboardAvailable { Button("Agent dashboard") { model.openAgentMap() } }
                    if LocalIntegrations.configured(.agentStatus) { Button("Refresh agent status") { model.refreshAgentStatus() }.buttonStyle(.plain).font(.system(size: 13)).foregroundStyle(Palette.tertiary) }
                }
            }
        }
    }
    private var conversationCard: some View {
        Card(title: "Conversation", systemImage: "bubble.left.and.bubble.right") {
            ContextBar(model: model)
            Text("Conversation turns: \(model.brainTurns)").font(.system(size: 12)).foregroundStyle(Palette.tertiary)
            if model.limitShare != nil { LimitShareView(model: model) }
            if !model.usageLine.isEmpty {
                Text(model.usageLine + "\n" + model.dayLine).font(.system(size: 12)).foregroundStyle(Palette.muted).textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button("Start new conversation") { model.newConversation() }
        }
    }
    private var guide: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Welcome to Conductor").font(.system(size: 15, weight: .semibold))
                Spacer()
                Button("Preferences") { showGuide = false }.buttonStyle(.plain).font(.system(size: 13)).foregroundStyle(Palette.tertiary)
            }.padding(.horizontal, 32).frame(height: 52).background(Palette.background)
            Rectangle().fill(Palette.hairline).frame(height: 1)
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    HStack(spacing: 0) {
                        ForEach(Array(["Brain", "Connection", "Mac access", "Try it"].enumerated()), id: \.offset) { index, title in
                            HStack(spacing: 8) {
                                ZStack {
                                    Circle().fill(index < guideStep ? Palette.success.opacity(0.18) : index == guideStep ? Palette.accent : Palette.raised)
                                    if index < guideStep { Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)).foregroundStyle(Palette.success) }
                                    else { Text("\(index + 1)").font(.system(size: 12, weight: .semibold)).foregroundStyle(index == guideStep ? Palette.panel : Palette.tertiary) }
                                }.frame(width: 24, height: 24)
                                Text(LocalizedStringKey(title)).font(.system(size: 13, weight: index == guideStep ? .semibold : .regular))
                                    .foregroundStyle(index == guideStep ? Palette.foreground : Palette.tertiary).lineLimit(1).fixedSize()
                            }
                            if index < 3 { Rectangle().fill(Palette.hairline).frame(height: 1).frame(maxWidth: .infinity).padding(.horizontal, 12) }
                        }
                    }.padding(.bottom, 8)
                    VStack(alignment: .leading, spacing: 8) {
                        Text(LocalizedStringKey(["Choose the brain behind Conductor.", "Connect Jev's actions.", "Let Conductor work on your Mac.", "Try a small request."][guideStep]))
                            .font(.system(size: 22, weight: .semibold))
                        Text(LocalizedStringKey(["Use the Claude Code or ChatGPT login you already have. You can change the brain later.", "Your Jev API key is saved in a file only your user can read. Check the connection when you are ready.", "These controls open the real macOS permission prompts. You can finish this later in Preferences.", "Open the local practice window, then hold Fn and say ‘click Blue’. Its buttons and text field are safe to try."][guideStep]))
                            .font(.system(size: 13)).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
                    }
                    switch guideStep {
                    case 0:
                        VStack(spacing: 8) { ForEach(BrainChoice.all) { choice in brainRow(choice) } }
                        caption("Finding a CLI does not verify its sign-in. Sign in with Claude Code or Codex before your first request.")
                        DisclosureGroup("Set paths manually") { cliCard.padding(.top, 10) }.font(.system(size: 13)).foregroundStyle(Palette.muted)
                    case 1: jevCard
                    case 2: permissionsCard
                    default:
                        Card {
                            HStack(spacing: 20) {
                                Image(systemName: "macwindow.on.rectangle").font(.system(size: 36, weight: .light))
                                    .foregroundStyle(Palette.tertiary).frame(width: 88, height: 88)
                                    .background(Palette.window, in: RoundedRectangle(cornerRadius: 12, style: .continuous)).accessibilityHidden(true)
                                VStack(alignment: .leading, spacing: 10) {
                                    Text("Hold Fn and speak").font(.system(size: 15, weight: .semibold))
                                    Text("Release to send. The practice window shows what actually changed.").font(.system(size: 13)).foregroundStyle(Palette.muted)
                                    Button("Open practice window") { model.openPractice?() }.buttonStyle(ConductorButtonStyle(prominent: true))
                                }
                            }
                        }
                        caption("The practice window is local. Voice requests use your configured brain and Jev connection.")
                    }
                }.padding(.horizontal, 40).padding(.vertical, 32).frame(maxWidth: 720, alignment: .leading).frame(maxWidth: .infinity, alignment: .leading)
            }
            Rectangle().fill(Palette.hairline).frame(height: 1)
            HStack(spacing: 10) {
                Button("Finish later") { showGuide = false }.buttonStyle(.plain).font(.system(size: 13)).foregroundStyle(Palette.tertiary)
                Spacer()
                if guideStep > 0 { Button("Back") { guideStep -= 1 } }
                Button(guideStep == 3 ? "Show command bar" : "Continue") {
                    if guideStep == 3 { showGuide = false; model.showCommandBar?() }
                    else { guideStep += 1 }
                }.buttonStyle(ConductorButtonStyle(prominent: true))
            }.padding(.horizontal, 32).frame(height: 60).background(Palette.background)
        }
    }
    private var brainCard: some View {
        Card(title: "Brain", systemImage: "brain.head.profile") {
            ConductorSwitchRow(title: "Plan before acting", isOn: $model.brainEnabled)
            caption("Choose a Claude Code or Codex CLI brain. Sign in through that CLI with your Claude or ChatGPT account first, then select the model here.")
            VStack(spacing: 8) { ForEach(BrainChoice.all) { choice in brainRow(choice) } }
        }
    }

    private func brainRow(_ choice: BrainChoice) -> some View {
        let selected = model.brainModel == choice.id
        let executableFound = choice.codex ? CodexBrain.binary() != nil : ClaudeBrain.binary() != nil
        return Button { model.selectBrain(choice, by: "settings") } label: {
            HStack(spacing: 12) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle").font(.system(size: 16)).foregroundStyle(selected ? Palette.accent : Palette.tertiary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(choice.name).font(.system(size: 13, weight: .semibold))
                    Text(executableFound ? choice.short : "CLI not found. Set its path in Advanced, install it, then sign in.")
                        .font(.system(size: 12)).foregroundStyle(executableFound ? Palette.tertiary : Palette.listening).fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
            }
            .padding(.horizontal, 12).padding(.vertical, 9)
            .contentShape(Rectangle())
            .background(selected ? Palette.accent.opacity(0.10) : Color.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(selected ? Palette.accent.opacity(0.55) : Palette.hairline))
        }.buttonStyle(.plain).disabled(!executableFound || !model.brainEnabled).opacity(model.brainEnabled ? 1 : 0.5)
    }

    private var cliCard: some View {
        Card(title: "Command-line tools", systemImage: "terminal") {
            caption("Leave a field blank to let Conductor search its usual install locations. Paths are saved in this Mac's app settings.")
            TextField("Claude Code executable path", text: $claudeCLIPath).textFieldStyle(.roundedBorder)
            TextField("Codex executable path", text: $codexCLIPath).textFieldStyle(.roundedBorder)
            TextField("Personal instructions file (optional)", text: $instructionsFilePath).textFieldStyle(.roundedBorder)
            caption("Local instructions are used when a new brain conversation starts.")
        }
    }

    private var whisperCard: some View {
        Card(title: "Local speech (Whisper)", systemImage: "waveform") {
            ConductorSwitchRow(title: "Use local Whisper for final transcription", isOn: $model.whisperEnabled)
                .disabled(!LocalWhisper.shared.installed)
            TextField("whisper-server executable path", text: $whisperServerPath).textFieldStyle(.roundedBorder)
            TextField("Whisper model file path", text: $whisperModelPath).textFieldStyle(.roundedBorder)
            caption(LocalWhisper.shared.installed ? "Whisper is ready. Audio is sent to the local server on this Mac." : "Install whisper.cpp and a model, then enter both paths to enable local Whisper. Apple Speech remains the fallback.")
        }
    }

    private var voiceCards: some View {
        VStack(alignment: .leading, spacing: 16) {
            Card(title: "Listen when", systemImage: "mic") {
                Picker("Listen when", selection: $model.continuousListening) {
                    Text("I hold Fn").tag(false)
                    Text("Continuous").tag(true)
                }.pickerStyle(.segmented).labelsHidden().frame(width: 320, alignment: .leading)
                caption(model.continuousListening ? "Conductor keeps listening between commands. Say ‘stop listening’ to turn off the microphone." : "Hold Fn or right Option, then release to send. A short tap lets you speak until the next tap. Option-Space listens for one command.")
                if model.continuousListening {
                    HStack {
                        Text("Send a continuous command").font(.system(size: 13))
                        Spacer()
                        Picker("Send a continuous command", selection: $model.sendByWord) {
                            Text("After ‘end command’ or Fn").tag(true)
                            Text("After a pause").tag(false)
                        }.labelsHidden().fixedSize()
                    }.padding(.top, 4)
                }
            }
            Card(title: "Speech language", systemImage: "globe") {
                Picker("Speech language", selection: $model.speechLanguage) {
                    Text("English").tag("en-US")
                    Text("Russian").tag("ru-RU")
                }.pickerStyle(.segmented).labelsHidden().frame(width: 320, alignment: .leading)
                caption(model.localSpeechAvailable ? "A new language takes effect next time the microphone starts." : "Apple Speech Recognition is not available. Enable Dictation in System Settings → Keyboard.")
            }
            Card(title: "Answers", systemImage: "text.bubble") {
                ConductorSwitchRow(title: "Spoken answers", isOn: $model.voiceFeedback)
                caption("Answers are always available as text in the command surface.")
            }
            Card(title: "Voice commands", systemImage: "quote.bubble") {
                Text("Say ‘cancel task’ or click Stop to interrupt a running task. Say ‘stop listening’ to turn off the microphone. Say ‘start over’ to clear the brain's conversation context.")
                    .font(.system(size: 13)).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var jevCard: some View {
        Card(title: "Jev actions", systemImage: "key.fill") {
            caption(model.keyConfigured ? "Your Jev API key is saved in a file only your user can read." : "Add a TypeSafe or OpenRouter API key. Conductor keeps it in a file only your user can read.")
            if model.keyConfigured {
                DisclosureGroup("Replace API key") { keyEntry.padding(.top, 8) }.font(.system(size: 13))
            } else { keyEntry }
            HStack(spacing: 12) {
                Text("Model: \(model.provider.model) via \(model.provider.name)").font(.system(size: 12)).foregroundStyle(Palette.tertiary)
                Spacer()
                Button(model.checkingConnection ? "Checking…" : "Check connection") { model.checkConnection() }
                    .disabled(!model.keyConfigured || model.busy || model.checkingConnection)
            }
            if !model.connectionDetail.isEmpty { Text(model.connectionDetail).font(.system(size: 13)).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true) }
        }
    }

    private var permissionsCard: some View {
        Card(title: "macOS permissions", systemImage: "hand.raised.fill") {
            permissionRow("Microphone and Speech Recognition", description: "Captures and transcribes voice commands.", enabled: model.microphoneGranted && model.speechGranted) { model.requestAudio() }
            Divider().overlay(Palette.hairline)
            permissionRow("Accessibility", description: "Reads available controls and performs UI actions.", enabled: model.accessibilityGranted) { model.requestAccessibility() }
            Divider().overlay(Palette.hairline)
            permissionRow("Screen Recording", description: "Lets the brain inspect a screenshot when a visual request needs it.", enabled: model.screenCaptureGranted) { model.requestScreenCapture() }
            caption("macOS may also prompt for Automation access when Conductor first controls an app. Grant access in System Settings to enable that app.")
        }
    }

    private var privacyCard: some View {
        Card(title: "Full access and privacy", systemImage: "lock.shield") {
            Text("The selected Claude Code or Codex CLI runs with its approval and sandbox checks bypassed. It can run commands, read and write files, use AppleScript and JXA, control apps, and use keyboard and pointer actions without asking you to approve each step in Conductor. Stop it with the Stop button or say ‘cancel task’. macOS privacy grants still apply and cannot be bypassed by the app.")
                .font(.system(size: 13)).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
            Text("Apple Speech may use Apple's network service when on-device recognition is unavailable; optional Whisper runs locally. The selected brain provider receives the request, screen text, and screenshots when needed. The selected Jev provider (TypeSafe or OpenRouter) receives your request, screen text, available choices, and action history, but no audio or screenshots. Secure accessibility fields are excluded, but the unrestricted CLI brain may read local files or other app data to carry out a request.")
                .font(.system(size: 13)).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
            ConductorSwitchRow(title: "Write diagnostic logs (may include screen text and commands)", isOn: $diagnosticsEnabled)
        }
    }

    private var keyEntry: some View {
        HStack {
            SecureField("TypeSafe or OpenRouter API key", text: $model.keyInput).textFieldStyle(.roundedBorder)
            Button("Save") { model.saveKey() }.disabled(model.keyInput.isEmpty)
        }
    }

    private func permissionRow(_ title: String, description: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(LocalizedStringKey(title)).font(.system(size: 13, weight: .medium))
                Text(LocalizedStringKey(description)).font(.system(size: 12)).foregroundStyle(Palette.tertiary)
            }
            Spacer()
            if enabled {
                Label("Enabled", systemImage: "checkmark.circle.fill").font(.system(size: 12, weight: .medium)).foregroundStyle(Palette.success)
            } else {
                Button("Open Settings", action: action)
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
                Text("Try a small request.").font(.system(size: 22, weight: .semibold))
                Text("Hold Fn and say ‘click Blue’, then release.\nHold Fn again to say ‘type hello world’. You can also click the microphone to listen for one command.").font(.system(size: 13)).foregroundStyle(Palette.muted)
            }
            RoundedRectangle(cornerRadius: 12, style: .continuous).fill(color).frame(height: 100)
                .overlay(Text(result).font(.system(size: 15, weight: .semibold)).foregroundStyle(Palette.background)).accessibilityLabel(result)
            HStack(spacing: 12) {
                Button { color = .cyan; result = "Blue selected" } label: { Text(verbatim: "Blue") }.accessibilityLabel(Text(verbatim: "Blue"))
                Button { color = .orange; result = "Coral selected" } label: { Text(verbatim: "Coral") }.accessibilityLabel(Text(verbatim: "Coral"))
                Button("Reset") { color = Palette.accent; result = "Pick a color with your voice."; text = "" }
            }.buttonStyle(ConductorButtonStyle())
            TextField("Practice text", text: $text).textFieldStyle(.roundedBorder).accessibilityLabel("Practice text")
            HStack {
                Button("Send message") { result = "Practice only: nothing was sent." }
                Text("A local practice action; nothing is sent externally.").font(.system(size: 12)).foregroundStyle(Palette.tertiary)
            }
            HStack {
                Button("Show command bar") { model.showCommandBar?() }
                Spacer()
                Text("No external side effects").font(.system(size: 12)).foregroundStyle(Palette.tertiary)
            }
        }.padding(32).frame(width: 475).background(Palette.window).foregroundStyle(Palette.foreground).preferredColorScheme(.dark).tint(Palette.accent)
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
                    .font(.system(size: 12)).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
                Text("Estimated from local session costs. Account use on other devices can affect this estimate.")
                    .font(.system(size: 12)).foregroundStyle(Palette.tertiary).fixedSize(horizontal: false, vertical: true)
            }
        } else if !model.usageLine.isEmpty {
            Text(model.usageLine).font(.system(size: 12)).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
        }
    }
}
