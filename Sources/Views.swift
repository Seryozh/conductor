import SwiftUI

enum Palette {
    static let background = Color(red: 0.055, green: 0.066, blue: 0.085)
    static let panel = Color(red: 0.087, green: 0.103, blue: 0.128)
    static let line = Color.white.opacity(0.085)
    static let accent = Color(red: 0.59, green: 0.94, blue: 0.80)
    static let muted = Color(red: 0.57, green: 0.63, blue: 0.68)
}
struct Card<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View { content.padding(18).background(Palette.panel, in: RoundedRectangle(cornerRadius: 16)).overlay(RoundedRectangle(cornerRadius: 16).stroke(Palette.line)) }
}
/// Settings for brain selection, speech, TypeSafe, privacy and macOS permissions.
struct SettingsView: View {
    @ObservedObject var model: AppModel
    @AppStorage("claudeCLIPath") private var claudeCLIPath = ""
    @AppStorage("codexCLIPath") private var codexCLIPath = ""
    @AppStorage("whisperServerPath") private var whisperServerPath = ""
    @AppStorage("whisperModelPath") private var whisperModelPath = ""
    @AppStorage("diagnosticsEnabled") private var diagnosticsEnabled = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Image(systemName: "waveform").foregroundStyle(Palette.accent)
                    Text("Conductor").font(.system(size: 24, weight: .semibold))
                    Spacer()
                    Button("Back to command bar") { model.showCommandBar?() }
                }
                Picker("Section", selection: $model.settingsTab) {
                    Text("General").tag("General")
                    Text("Jev activity").tag("Jev activity")
                }.pickerStyle(.segmented).labelsHidden()
                if model.settingsTab == "Jev activity" { JevActivityView(model: model) }
                else {
                    if let issue = model.billingIssue { Text(issue).foregroundStyle(.orange).font(.system(size: 12)) }
                    setup
                }
            }.padding(24)
        }
        .frame(minWidth: 620, minHeight: 530)
        .background(Palette.background).foregroundStyle(.white).preferredColorScheme(.dark)
    }

    private var setup: some View {
        VStack(alignment: .leading, spacing: 16) {
            brainCard
            pathsCard
            voiceCard
            phrasesCard
            jevCard
            permissionsCard
            privacyCard
        }
    }

    private var brainCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("Brain", systemImage: "brain.head.profile").font(.system(size: 16, weight: .semibold))
                    Spacer()
                    Toggle("Plan before acting", isOn: $model.brainEnabled).toggleStyle(.switch).controlSize(.small).font(.system(size: 12))
                }
                Text("Claude Code and Codex can each run Conductor's reasoning brain. Claude uses your Claude Code login and supported subscription. Codex uses your ChatGPT login. Pick the model you want to use.")
                    .font(.system(size: 12)).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
                ForEach(BrainChoice.all) { choice in brainRow(choice) }
                Divider()
                ContextBar(model: model)
                if !model.usageLine.isEmpty { Text(model.usageLine + "\n" + model.dayLine).font(.system(size: 11)).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true) }
                HStack {
                    Text("Conversation turns: \(model.brainTurns). The brain keeps context during this session.").font(.system(size: 11)).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    Button("Start new conversation") { model.newConversation() }.font(.system(size: 12))
                }
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
                    Text(executableFound ? choice.short : "CLI not found. Set its path below, install it, then sign in.")
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
                Divider()
                Toggle("Use local Whisper for final transcription", isOn: $model.whisperEnabled)
                    .toggleStyle(.switch).controlSize(.small)
                    .disabled(!LocalWhisper.shared.installed)
                TextField("whisper-server executable path", text: $whisperServerPath).textFieldStyle(.roundedBorder)
                TextField("Whisper model file path", text: $whisperModelPath).textFieldStyle(.roundedBorder)
                Text(LocalWhisper.shared.installed ? "Whisper is ready. Audio is sent to the local server on this Mac." : "Install whisper.cpp and a model, then enter both paths to enable local Whisper. Apple Speech remains the fallback.")
                    .font(.system(size: 11)).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var voiceCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 11) {
                Label("Voice", systemImage: "mic").font(.system(size: 16, weight: .semibold))
                Toggle("Speak answers aloud (otherwise show text under the command bar)", isOn: $model.voiceFeedback).toggleStyle(.switch).controlSize(.small)
                Toggle("Continuous listening (otherwise hold Fn or activate one command)", isOn: $model.continuousListening).toggleStyle(.switch).controlSize(.small)
                Toggle("Send after saying ‘end command’ or pressing Fn (otherwise send after a pause)", isOn: $model.sendByWord).toggleStyle(.switch).controlSize(.small).disabled(!model.continuousListening)
                HStack {
                    Text("Speech language")
                    Spacer()
                    Picker("Speech language", selection: $model.speechLanguage) {
                        Text("English").tag("en-US")
                        Text("Russian").tag("ru-RU")
                    }.pickerStyle(.segmented).labelsHidden().frame(width: 200)
                }
                Text(model.localSpeechAvailable ? "Speech is available on this Mac. A new language takes effect next time the microphone starts." : "Apple Speech Recognition is not available. Enable Dictation in System Settings → Keyboard.")
                    .font(.system(size: 11)).foregroundStyle(Palette.muted)
            }.font(.system(size: 12))
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
                Text(model.keyConfigured ? "Your TypeSafe API key is stored in macOS Keychain." : "Add a TypeSafe API key. Conductor stores it only in macOS Keychain.")
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
                Text("Voice audio is transcribed on this Mac. The selected brain provider receives the request, screen text, and screenshots when needed. TypeSafe receives your request, screen text, available choices, and action history, but no audio or screenshots. Secure accessibility fields are excluded, but the unrestricted CLI brain may read local files or other app data to carry out a request.")
                    .font(.system(size: 12)).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
                Toggle("Write diagnostic logs (may include screen text and commands)", isOn: $diagnosticsEnabled)
                    .toggleStyle(.switch).controlSize(.small)
            }
        }
    }

    private var keyEntry: some View {
        HStack {
            SecureField("TypeSafe API key", text: $model.keyInput).textFieldStyle(.roundedBorder)
            Button("Save") { model.saveKey() }.disabled(model.keyInput.isEmpty)
        }
    }

    private func permissionRow(_ title: String, description: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 12, weight: .medium))
                Text(description).font(.system(size: 10)).foregroundStyle(Palette.muted)
            }
            Spacer()
            Button(enabled ? "Enabled" : "Open Settings", action: action).disabled(enabled)
        }
    }
}

/// The everyday interface. Detailed activity stays in the menu-bar settings window.
/// The command bar shows whether the microphone is listening or the app is busy.
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
    var color: Color {
        switch self {
        case .ready: return Palette.muted
        case .listening: return Color(red: 1.0, green: 0.33, blue: 0.33)
        case .recognizing: return .yellow
        case .thinking: return Color(red: 0.72, green: 0.58, blue: 1.0)
        case .acting: return .orange
        case .checking: return Color(red: 0.45, green: 0.7, blue: 1.0)
        case .attention: return .orange
        }
    }
}

struct CommandBarView: View {
    @ObservedObject var model: AppModel
    @FocusState private var editing: Bool
    let openSettings: () -> Void
    let releaseKeyboard: () -> Void
    /// Room for the brain chip.
    static let width: CGFloat = 548

    private var command: String {
        if !model.liveTranscript.isEmpty { return model.liveTranscript }
        if !model.transcript.isEmpty { return model.transcript }
        return model.micEnabled ? "Speak your command…" : "Hold Fn and speak, or type a command…"
    }
    private var stateLabel: String {
        if model.requestingAudio { return "Allow microphone access" }
        if !model.keyConfigured || !model.accessibilityGranted { return "Finish setup in Settings" }
        switch model.voiceState {
        case .ready: return "Ready · hold Fn and speak"
        case .listening: return model.busy ? "Listening · say ‘cancel task’ to stop" : model.holdingToTalk ? "Listening · release Fn when done" : model.tapListening ? "Listening · say ‘end command’ or press Fn to send" : model.continuousListening ? (model.wordMode ? "Listening · say ‘end command’ or press Fn to send" : "Listening continuously") : "Listening · pause when finished"
        case .recognizing: return "Not listening · transcribing…"
        case .thinking: return "Not listening · thinking…"
        case .acting: return "Not listening · acting: " + model.detail
        case .checking: return "Not listening · checking the result…"
        case .attention: return model.detail
        }
    }
    private func submit() {
        editing = false
        releaseKeyboard()
        model.runTyped()
    }
    var body: some View {
        HStack(spacing: 11) {
            Button {
                editing = false
                releaseKeyboard()
                model.toggleListening()
            } label: {
                Image(systemName: model.voiceState.icon)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(model.voiceState.color)
                    .frame(width: 34, height: 36)
                    .background(model.voiceState.color.opacity(model.voiceState == .listening ? 0.10 + model.level * 0.35 : 0.10), in: RoundedRectangle(cornerRadius: 10))
            }.buttonStyle(.plain)
                .accessibilityLabel(model.micEnabled ? "Turn mic off" : "Turn mic on")
                .help("Toggle listening · Option–Space")
            VStack(alignment: .leading, spacing: 3) {
                TextField("", text: $model.typedCommand,
                    prompt: Text(command).foregroundColor(model.transcript.isEmpty && model.liveTranscript.isEmpty ? Palette.muted : .white))
                    .textFieldStyle(.plain).font(.system(size: 13, weight: .medium))
                    .focused($editing).onSubmit { submit() }
                    .accessibilityLabel("Command transcript")
                HStack(spacing: 5) {
                    Circle().fill(model.voiceState.color).frame(width: 6, height: 6)
                    Text(stateLabel).lineLimit(1).truncationMode(.tail).foregroundStyle(model.voiceState.color)
                    if model.queuedCount > 0 { Text("· queued \(model.queuedCount)").foregroundStyle(Palette.muted) }
                    if model.shotsThisCommand > 0 { Label("\(model.shotsThisCommand)", systemImage: "camera.fill").foregroundStyle(Palette.muted).help("Screenshots sent to the brain for this command") }
                }.font(.system(size: 11, weight: .medium))
            }.frame(maxWidth: .infinity, alignment: .leading)
            // The brain at a glance, and one click to change it.
            Menu {
                ForEach(BrainChoice.all) { choice in
                    Button((choice.id == model.brainModel ? "✓ " : "    ") + choice.name + "  ·  " + choice.short) { model.selectBrain(choice, by: "bar") }
                        .disabled(choice.codex && CodexBrain.binary() == nil)
                }
                Divider()
                Button("Start new conversation") { model.newConversation() }
                Button("Settings…", action: openSettings)
            } label: {
                Text(model.brainEnabled ? model.brainChoice.name : "No brain").font(.system(size: 11, weight: .semibold))
            }
            .menuStyle(.borderlessButton).menuIndicator(.visible).fixedSize()
            .tint(Palette.accent)
            .help("Choose the reasoning model used for requests.")
            .accessibilityLabel("Brain model")
            if !model.typedCommand.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Button { submit() } label: {
                    Image(systemName: "arrow.up").font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Palette.background).frame(width: 27, height: 27)
                        .background(Palette.accent, in: Circle())
                }.buttonStyle(.plain).accessibilityLabel("Run command").help("Run command · Return")
            }
            if model.busy {
                Button { model.cancelCurrentTask() } label: {
                    Image(systemName: "stop.fill").font(.system(size: 10)).frame(width: 26, height: 28)
                }.buttonStyle(.plain).foregroundStyle(Palette.muted).accessibilityLabel("Stop task")
            } else if !model.keyConfigured || !model.accessibilityGranted || model.billingIssue != nil {
                Button(action: openSettings) { Image(systemName: "exclamationmark.circle").foregroundStyle(.orange) }
                    .buttonStyle(.plain).accessibilityLabel("Open Settings")
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .frame(width: Self.width, height: 60)
        .background(Palette.background.opacity(0.97), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(model.voiceState == .ready ? Color.white.opacity(0.12) : model.voiceState.color.opacity(0.85), lineWidth: model.voiceState == .listening ? 2 : 1))
        .foregroundStyle(.white).preferredColorScheme(.dark)
        .onChange(of: model.busy) { _, busy in if busy { editing = false } }
        .onExitCommand { editing = false; releaseKeyboard() }
    }
}

struct PracticeView: View {
    @ObservedObject var model: AppModel
    @State private var color = Palette.accent
    @State private var result = "Pick a color with your voice."
    @State private var text = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("Practice voice commands").font(.system(size: 26, weight: .medium, design: .rounded))
            Text("Turn the mic on once and say “click Blue”.\nPause, then say “type hello world”.").font(.system(size: 13)).foregroundStyle(Palette.muted)
            RoundedRectangle(cornerRadius: 20).fill(color).frame(height: 100).overlay(Text(result).font(.system(size: 18, weight: .medium)).foregroundStyle(.black)).accessibilityLabel(result)
            HStack(spacing: 12) {
                Button("Blue") { color = .cyan; result = "Blue selected" }.accessibilityLabel("Blue")
                Button("Coral") { color = .orange; result = "Coral selected" }.accessibilityLabel("Coral")
                Button("Reset") { color = Palette.accent; result = "Pick a color with your voice."; text = "" }
            }.buttonStyle(.bordered).controlSize(.large)
            TextField("Practice text", text: $text).textFieldStyle(.roundedBorder).accessibilityLabel("Practice text")
            HStack {
                Button("Send message") { result = "Practice only: nothing was sent." }
                Text("A local practice action; nothing is sent externally.").font(.system(size: 10)).foregroundStyle(Palette.muted)
            }
            HStack { Button("Show command bar") { model.showCommandBar?() }; Spacer(); Text("No external side effects").font(.system(size: 10)).foregroundStyle(Palette.muted) }
        }.padding(30).frame(width: 475).background(Palette.background).foregroundStyle(.white).preferredColorScheme(.dark)
    }
}


/// The last answer as text, shown below the command bar.
struct AnswerView: View {
    @ObservedObject var model: AppModel
    static let width: CGFloat = 660
    static let textFont = NSFont.systemFont(ofSize: 17)
    static let lineSpacing: CGFloat = 5
    static let horizontalPadding: CGFloat = 20
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Text("Answer").font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.muted)
                if !model.modelLabel.isEmpty {
                    Label(model.modelLabel, systemImage: "brain.head.profile").font(.system(size: 12, weight: .medium))
                        .foregroundStyle(model.modelLabel.contains("fallback") ? Color.orange : Palette.accent)
                }
                Spacer()
                Button { model.dismissAnswer() } label: { Image(systemName: "xmark").font(.system(size: 12, weight: .semibold)) }
                    .buttonStyle(.plain).foregroundStyle(Palette.muted).accessibilityLabel("Close answer")
            }
            ScrollView {
                Text(model.answerText).font(Font(Self.textFont)).lineSpacing(Self.lineSpacing).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading).fixedSize(horizontal: false, vertical: true)
            }
            if model.shotsThisCommand > 0, let shot = model.lastScreenshot {
                HStack(spacing: 10) {
                    Image(nsImage: shot).resizable().scaledToFit().frame(height: 48)
                        .clipShape(RoundedRectangle(cornerRadius: 4)).overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.white.opacity(0.2)))
                    VStack(alignment: .leading, spacing: 2) {
                        Label("Screenshots sent to the brain: \(model.shotsThisCommand)", systemImage: "camera.viewfinder")
                        Text("\(model.shotsToday) today · latest screenshot at left").foregroundStyle(Palette.muted)
                    }.font(.system(size: 12))
                }
            }
            Divider().overlay(Color.white.opacity(0.1))
            ContextBar(model: model)
        }
        .padding(.horizontal, Self.horizontalPadding).padding(.vertical, 14)
        .frame(width: Self.width).frame(maxHeight: .infinity, alignment: .top)
        .background(Palette.background, in: RoundedRectangle(cornerRadius: 14))   // opaque: text behind showed through
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.12), lineWidth: 1))
        .foregroundStyle(.white).preferredColorScheme(.dark)
    }
}

/// Estimated share of the subscription usage window used by one command.
/// How full the brain's conversation memory is: green, yellow, then red near the limit.
struct ContextBar: View {
    @ObservedObject var model: AppModel
    private var color: Color { model.contextFraction >= 0.85 ? Color(red: 1, green: 0.35, blue: 0.35) : model.contextFraction >= 0.6 ? .yellow : Palette.accent }
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.08))
                    Capsule().fill(color).frame(width: max(model.contextUsed > 0 ? 4 : 0, geometry.size.width * model.contextFraction))
                }
            }.frame(height: 5)
            Text(model.contextLabel).font(.system(size: 12, weight: .medium)).foregroundStyle(model.contextFraction >= 0.85 ? color : Palette.muted)
        }
    }
}
