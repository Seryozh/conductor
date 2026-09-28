import Foundation

/// GPT models (GPT-6 Astra, GPT-6 Luna) as Conductor's brain, through the Codex CLI on the user's
/// ChatGPT plan. Same instruction, answer contract and
/// full access to the Mac as ClaudeBrain (ClaudeBrain.prompt, ClaudeBrain.parse, no sandbox).
/// Each command is one `codex exec` run; later commands resume the same Codex thread, so the
/// conversation carries over. Codex keeps its own base instructions, because they teach the model
/// its shell tool (replacing them left GPT unable to read a file); Jev's instruction goes in as
/// developer instructions.
final class CodexBrain: @unchecked Sendable, BrainPlanner {
    /// Use the CLI's signed-in ChatGPT account, not provider keys inherited from
    /// the app's launcher or a terminal session.
    static func subscriptionEnvironment(_ source: [String: String] = ProcessInfo.processInfo.environment) -> [String: String] {
        source.filter { key, _ in
            let name = key.uppercased()
            // CODEX_HOME may contain the CLI's signed-in account. Keep that
            // location while dropping inherited provider credential overrides.
            return name == "CODEX_HOME" || (!name.hasPrefix("OPENAI_") && !name.hasPrefix("AZURE_OPENAI_")
                && !name.hasPrefix("CODEX_") && !name.hasPrefix("CHATGPT_"))
        }
    }

    static func binary() -> URL? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let configured = UserDefaults.standard.string(forKey: "codexCLIPath")
        let paths = [configured, "/Applications/ChatGPT.app/Contents/Resources/codex", "/Applications/Codex.app/Contents/Resources/codex",
                     home + "/.local/bin/codex", "/opt/homebrew/bin/codex", "/usr/local/bin/codex"]
            .compactMap { $0 }
        return paths.first { FileManager.default.isExecutableFile(atPath: $0) }.map { URL(fileURLWithPath: $0) }
    }
    static var instructions: String { ClaudeBrain.runtimePrompt + """


    TOOLS IN THIS RUNTIME: you run inside the Codex CLI with full access to the user's Mac. The shell can read files and run commands. When a request needs a file or local state, inspect it yourself before answering. Do not claim that a file or screen is inaccessible when the available tools can read it. Where an instruction names Read, Glob, Grep or Bash, use the shell; use view_image to inspect a local picture. Prefer the app's returned action fields for operations it can perform directly. When shell tools are needed, batch independent reads and keep the result focused on the user's request.
    """ }
    /// A TOML basic string for `codex -c key=value`.
    static func tomlString(_ text: String) -> String {
        var out = "\""
        for scalar in text.unicodeScalars {
            switch scalar {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            default:
                if scalar.value < 0x20 || scalar.value == 0x7F { out += String(format: "\\u%04X", scalar.value) }
                else { out.unicodeScalars.append(scalar) }
            }
        }
        return out + "\""
    }

    var onActivity: ((String) -> Void)?
    var enabled: Bool { UserDefaults.standard.object(forKey: "brainEnabled") as? Bool ?? true }
    var available: Bool { Self.binary() != nil }
    let fixedChoice: BrainChoice?
    init(choice: BrainChoice? = nil) { fixedChoice = choice }
    var choice: BrainChoice { fixedChoice ?? BrainChoice.stored }

    private let lock = NSLock()
    private var thread: String?
    private var threadModel: String?
    private var running: Process?
    private(set) var turns = 0
    private(set) var lastUsage = BrainUsage()
    private(set) var fixedTokens = 0
    private var threadInput = 0, threadOutput = 0
    var resetNote: String?

    func warm() {}   // nothing stays running between commands

    func plan(_ message: String, image: Data?, timeout: TimeInterval) async throws -> BrainReply {
        guard let binary = Self.binary() else { throw VoiceError.message("Codex CLI was not found. Install it, sign in, or choose its executable in Settings.") }
        let wanted = choice
        let (resume, note) = lock.withLock { () -> (String?, String?) in
            if threadModel != wanted.model { thread = nil; threadModel = wanted.model; turns = 0; fixedTokens = 0; threadInput = 0; threadOutput = 0 }
            let resume = thread
            let note = resetNote
            resetNote = nil
            return (resume, note)
        }
        var text = message
        if let note { text = note + "\n\n" + text }
        text += "\n\n(Reply with the one JSON object only.)"
        var imageFile: URL?
        if let image {
            let file = FileManager.default.temporaryDirectory.appendingPathComponent("jev-codex-\(UUID().uuidString).jpg")
            try image.write(to: file); imageFile = file
        }
        defer { if let imageFile { try? FileManager.default.removeItem(at: imageFile) } }
        var args = ["exec"]
        if let resume { args += ["resume", resume] }
        args += ["--json", "--ignore-user-config", "--skip-git-repo-check", "--dangerously-bypass-approvals-and-sandbox",
                 "-m", wanted.model, "-c", "model_reasoning_effort=" + wanted.effort, "-c", "developer_instructions=" + Self.tomlString(Self.instructions)]
        if let imageFile { args += ["-i", imageFile.path] }
        args += ["--", text]

        let outcome = try await run(binary, args, timeout: timeout)
        lock.withLock {
            if resume == nil, let started = outcome.thread { thread = started; threadInput = 0; threadOutput = 0 }
            turns += 1
            var usage = BrainUsage()
            // Resumed runs report running totals. Count only this command's delta.
            usage.inputTokens = max(0, outcome.input - threadInput)
            usage.outputTokens = max(0, outcome.output - threadOutput)
            threadInput = outcome.input; threadOutput = outcome.output
            if let file = Self.rollout(thread: thread), let size = Self.contextSize(file) {
                usage.contextUsed = size.last; usage.contextWindow = size.window
                if fixedTokens == 0 { fixedTokens = max(0, (Self.firstCallInput(file) ?? size.last) - 2500) }
            } else {
                usage.contextUsed = lastUsage.contextUsed; usage.contextWindow = lastUsage.contextWindow
            }
            usage.model = wanted.model
            usage.sevenDay = Self.weekUsed(thread: thread)
            lastUsage = usage
        }
        var reply = try ClaudeBrain.parse(outcome.answer)
        reply.toolActions = outcome.tools   // work the brain did itself is not "said but not done"
        return reply
    }

    private struct Outcome { var thread: String?; var answer = ""; var tools: [String] = []; var input = 0; var output = 0 }

    private func run(_ binary: URL, _ args: [String], timeout: TimeInterval) async throws -> Outcome {
        let task = Process()
        task.executableURL = binary
        task.arguments = args
        task.environment = Self.subscriptionEnvironment()
        task.currentDirectoryURL = FileManager.default.homeDirectoryForCurrentUser
        task.standardInput = FileHandle.nullDevice   // Codex waits for extra stdin input otherwise
        let stdout = Pipe(); task.standardOutput = stdout; task.standardError = FileHandle.nullDevice
        var outcome = Outcome(), failure: String?
        let parseLock = NSLock()
        let watchdog = BrainIdleWatchdog(timeout: timeout) {
            parseLock.withLock { if failure == nil { failure = "Codex produced no activity for \(Int(timeout)) seconds. The request is unfinished." } }
            if task.isRunning { task.terminate() }
        }
        defer { watchdog.stop() }
        func handle(_ line: Data) {
            guard let event = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else { return }
            watchdog.activity()
            let kind = event["type"] as? String ?? ""
            let item = event["item"] as? [String: Any] ?? [:]
            parseLock.lock(); defer { parseLock.unlock() }
            switch kind {
            case "turn.started": watchdog.begin("turn")
            case "thread.started":
                outcome.thread = event["thread_id"] as? String
                // Retain the conversation even when this turn times out before an answer.
                lock.withLock { if running === task { thread = outcome.thread } }
            case "item.started":
                if let id = item["id"] as? String { watchdog.begin(id) }
                let label = item["type"] as? String == "reasoning" ? "Thinking…" : "Working on your Mac…"
                DispatchQueue.main.async { [weak self] in self?.onActivity?(label) }
            case "item.completed":
                if let id = item["id"] as? String { watchdog.end(id) }
                if item["type"] as? String == "agent_message", let text = item["text"] as? String { outcome.answer = text }
                if item["type"] as? String == "command_execution", let command = item["command"] as? String { outcome.tools.append(String(command.prefix(300))) }
            case "turn.completed":
                watchdog.endAll()
                let usage = event["usage"] as? [String: Any] ?? [:]
                outcome.input += usage["input_tokens"] as? Int ?? 0; outcome.output += usage["output_tokens"] as? Int ?? 0
            case "turn.failed", "error":
                watchdog.endAll()
                if failure == nil { failure = ((event["error"] as? [String: Any])?["message"] as? String) ?? (event["message"] as? String) ?? "Codex returned an error." }
            default: break
            }
        }
        // One reader thread owns the pipe until EOF, so nothing is parsed after the result is read.
        let reader = stdout.fileHandleForReading
        let readerDone = DispatchSemaphore(value: 0)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            task.terminationHandler = { _ in continuation.resume() }
            do { try task.run() } catch { task.terminationHandler = nil; continuation.resume(throwing: error); return }
            lock.lock(); running = task; lock.unlock()
            DispatchQueue.global().async {
                var buffer = Data()
                while true {
                    let data = reader.availableData
                    if data.isEmpty { break }
                    buffer.append(data)
                    while let newline = buffer.firstIndex(of: 0x0A) {
                        let line = buffer[buffer.startIndex..<newline]; buffer.removeSubrange(buffer.startIndex...newline)
                        handle(Data(line))
                    }
                }
                if !buffer.isEmpty { handle(buffer) }
                readerDone.signal()
            }
        }
        lock.withLock { running = nil }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            DispatchQueue.global().async {
                _ = readerDone.wait(timeout: .now() + 3)
                continuation.resume()
            }
        }
        let (result, problem) = parseLock.withLock { (outcome, failure) }
        if task.terminationReason == .uncaughtSignal, problem == nil { throw CancellationError() }
        if let problem {
            if !result.tools.isEmpty { DebugLog.write("CODEX FAILED after \(result.tools.count) commands: " + result.tools.map { String($0.prefix(120)) }.joined(separator: " | ")) }
            throw VoiceError.message("Codex: " + problem)
        }
        guard !result.answer.isEmpty else { throw VoiceError.message("Codex returned no answer.") }
        return result
    }

    /// The thread's own log, where Codex records every model call.
    static func rollout(thread: String?) -> URL? {
        guard let thread else { return nil }
        let configured = ProcessInfo.processInfo.environment["CODEX_HOME"].flatMap { $0.isEmpty ? nil : $0 }
        let home = configured.map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex", isDirectory: true)
        let sessions = home.appendingPathComponent("sessions", isDirectory: true)
        let day = DateFormatter(); day.dateFormat = "yyyy/MM/dd"
        for date in [Date(), Date().addingTimeInterval(-86400)] {
            let folder = sessions.appendingPathComponent(day.string(from: date))
            if let name = (try? FileManager.default.contentsOfDirectory(atPath: folder.path))?.first(where: { $0.contains(thread) }) { return folder.appendingPathComponent(name) }
        }
        return nil
    }
    private static func tail(_ file: URL, _ bytes: UInt64) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: file) else { return nil }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        try? handle.seek(toOffset: size > bytes ? size - bytes : 0)
        return String(decoding: handle.readDataToEndOfFile(), as: UTF8.self)
    }
    /// The last model call's input (the real conversation size) and the context window.
    static func contextSize(_ file: URL) -> (last: Int, window: Int)? {
        guard let text = tail(file, 400_000) else { return nil }
        for line in text.split(separator: "\n").reversed() where line.contains("\"token_count\"") && line.contains("last_token_usage") {
            guard let info = tokenInfo(line), let last = (info["last_token_usage"] as? [String: Any])?["input_tokens"] as? Int else { continue }
            return (last, info["model_context_window"] as? Int ?? 258_400)
        }
        return nil
    }
    /// The first model call of the thread: instruction, tools and the first message.
    static func firstCallInput(_ file: URL) -> Int? {
        guard let handle = try? FileHandle(forReadingFrom: file) else { return nil }
        defer { try? handle.close() }
        let head = String(decoding: handle.readData(ofLength: 3_000_000), as: UTF8.self)
        for line in head.split(separator: "\n") where line.contains("\"token_count\"") && line.contains("last_token_usage") {
            if let info = tokenInfo(line), let first = (info["last_token_usage"] as? [String: Any])?["input_tokens"] as? Int { return first }
        }
        return nil
    }
    private static func tokenInfo(_ line: Substring) -> [String: Any]? {
        guard let event = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any] else { return nil }
        return (event["payload"] as? [String: Any])?["info"] as? [String: Any]
    }
    /// The ChatGPT plan's weekly Codex usage (0...1), from the thread's own log.
    static func weekUsed(thread: String?) -> Double? {
        guard let file = rollout(thread: thread), let text = tail(file, 200_000),
              let range = text.range(of: "\"used_percent\":", options: .backwards) else { return nil }
        let number = text[range.upperBound...].prefix { $0.isNumber || $0 == "." }
        return Double(number).map { $0 / 100 }
    }

    func interrupt() {
        lock.lock(); let task = running; lock.unlock()
        if let task, task.isRunning { task.terminate() }
    }

    /// A new conversation starts a fresh Codex thread; the old one is archived, not deleted.
    func stop() {
        interrupt()
        lock.lock(); let old = thread; thread = nil; threadModel = nil; turns = 0; fixedTokens = 0; threadInput = 0; threadOutput = 0; lastUsage.contextUsed = 0; lock.unlock()
        if let old, let binary = Self.binary() {
            let archive = Process(); archive.executableURL = binary; archive.arguments = ["archive", old]
            archive.environment = Self.subscriptionEnvironment()
            archive.standardInput = FileHandle.nullDevice; archive.standardOutput = FileHandle.nullDevice; archive.standardError = FileHandle.nullDevice
            try? archive.run()
        }
    }
}
