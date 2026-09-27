import Foundation

/// GPT models (GPT-6 Astra, GPT-6 Luna) as Jev Voice's brain, through the Codex CLI on the user's
/// ChatGPT plan. Same instruction, answer contract and
/// full access to the Mac as ClaudeBrain (ClaudeBrain.prompt, ClaudeBrain.parse, no sandbox).
/// Each command is one `codex exec` run; later commands resume the same Codex thread, so the
/// conversation carries over. Codex keeps its own base instructions, because they teach the model
/// its shell tool (replacing them left GPT unable to read a file); Jev's instruction goes in as
/// developer instructions.
final class CodexBrain: @unchecked Sendable, BrainPlanner {
    static func binary() -> URL? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let configured = UserDefaults.standard.string(forKey: "codexCLIPath")
        let paths = [configured, "/Applications/ChatGPT.app/Contents/Resources/codex", "/Applications/Codex.app/Contents/Resources/codex",
                     home + "/.local/bin/codex", "/opt/homebrew/bin/codex", "/usr/local/bin/codex"]
            .compactMap { $0 }
        return paths.first { FileManager.default.isExecutableFile(atPath: $0) }.map { URL(fileURLWithPath: $0) }
    }
    static let instructions = ClaudeBrain.prompt + """


    TOOLS IN THIS RUNTIME: you run inside the Codex CLI with full access to the user's Mac. The shell can read files and run commands. When a request needs a file or local state, inspect it yourself before answering. Do not claim that a file or screen is inaccessible when the available tools can read it.
    """
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
    var resetNote: String?

    func warm() {}   // nothing stays running between commands

    func plan(_ message: String, image: Data?, timeout: TimeInterval) async throws -> BrainReply {
        guard let binary = Self.binary() else { throw VoiceError.message("Codex CLI was not found. Install it, sign in, or choose its executable in Settings.") }
        let wanted = choice
        lock.lock()
        if threadModel != wanted.model { thread = nil; threadModel = wanted.model; turns = 0; fixedTokens = 0 }
        let resume = thread
        let note = resetNote; resetNote = nil
        lock.unlock()
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
        lock.lock()
        if resume == nil, let started = outcome.thread { thread = started }
        turns += 1
        var usage = BrainUsage()
        usage.inputTokens = outcome.input; usage.outputTokens = outcome.output
        usage.contextUsed = outcome.input / max(1, outcome.tools.count + 1)   // roughly the last model call
        usage.contextWindow = 272_000
        usage.model = wanted.model
        usage.sevenDay = Self.weekUsed(thread: thread)
        lastUsage = usage
        if fixedTokens == 0 { fixedTokens = max(0, usage.contextUsed - 2500) }
        lock.unlock()
        var reply = try ClaudeBrain.parse(outcome.answer)
        reply.toolActions = outcome.tools   // work the brain did itself is not "said but not done"
        return reply
    }

    private struct Outcome { var thread: String?; var answer = ""; var tools: [String] = []; var input = 0; var output = 0 }

    private func run(_ binary: URL, _ args: [String], timeout: TimeInterval) async throws -> Outcome {
        let task = Process()
        task.executableURL = binary
        task.arguments = args
        task.currentDirectoryURL = FileManager.default.homeDirectoryForCurrentUser
        task.standardInput = FileHandle.nullDevice   // Codex waits for extra stdin input otherwise
        let stdout = Pipe(); task.standardOutput = stdout; task.standardError = FileHandle.nullDevice
        var outcome = Outcome(), failure: String?
        let parseLock = NSLock()
        func fail(_ text: String) { parseLock.lock(); if failure == nil { failure = text }; parseLock.unlock() }
        func handle(_ line: Data) {
            guard let event = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else { return }
            let kind = event["type"] as? String ?? ""
            let item = event["item"] as? [String: Any] ?? [:]
            parseLock.lock(); defer { parseLock.unlock() }
            switch kind {
            case "thread.started": outcome.thread = event["thread_id"] as? String
            case "item.started" where item["type"] as? String == "command_execution":
                DispatchQueue.main.async { [weak self] in self?.onActivity?("Working on your Mac…") }
            case "item.completed":
                if item["type"] as? String == "agent_message", let text = item["text"] as? String { outcome.answer = text }
                if item["type"] as? String == "command_execution", let command = item["command"] as? String { outcome.tools.append(String(command.prefix(300))) }
            case "turn.completed":
                let usage = event["usage"] as? [String: Any] ?? [:]
                outcome.input += usage["input_tokens"] as? Int ?? 0; outcome.output += usage["output_tokens"] as? Int ?? 0
            case "turn.failed", "error":
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
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) { if task.isRunning { fail("Codex did not respond within \(Int(timeout)) seconds."); task.terminate() } }
        }
        lock.lock(); running = nil; lock.unlock()
        _ = readerDone.wait(timeout: .now() + 3)
        parseLock.lock(); let result = outcome, problem = failure; parseLock.unlock()
        if task.terminationReason == .uncaughtSignal, problem == nil { throw CancellationError() }
        if let problem, result.answer.isEmpty { throw VoiceError.message("Codex: " + problem) }
        guard !result.answer.isEmpty else { throw VoiceError.message("Codex returned no answer.") }
        return result
    }

    /// The ChatGPT plan's weekly Codex usage (0...1), from the thread's own log.
    static func weekUsed(thread: String?) -> Double? {
        guard let thread else { return nil }
        let sessions = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex/sessions")
        let day = DateFormatter(); day.dateFormat = "yyyy/MM/dd"
        for date in [Date(), Date().addingTimeInterval(-86400)] {
            let folder = sessions.appendingPathComponent(day.string(from: date))
            guard let name = (try? FileManager.default.contentsOfDirectory(atPath: folder.path))?.first(where: { $0.contains(thread) }),
                  let handle = try? FileHandle(forReadingFrom: folder.appendingPathComponent(name)) else { continue }
            defer { try? handle.close() }
            let size = (try? handle.seekToEnd()) ?? 0
            try? handle.seek(toOffset: size > 200_000 ? size - 200_000 : 0)
            let tail = String(decoding: handle.readDataToEndOfFile(), as: UTF8.self)
            guard let range = tail.range(of: "\"used_percent\":", options: .backwards) else { return nil }
            let number = tail[range.upperBound...].prefix { $0.isNumber || $0 == "." }
            return Double(number).map { $0 / 100 }
        }
        return nil
    }

    func interrupt() {
        lock.lock(); let task = running; lock.unlock()
        if let task, task.isRunning { task.terminate() }
    }

    /// A new conversation starts a fresh Codex thread; the old one is archived, not deleted.
    func stop() {
        interrupt()
        lock.lock(); let old = thread; thread = nil; threadModel = nil; turns = 0; fixedTokens = 0; lastUsage.contextUsed = 0; lock.unlock()
        if let old, let binary = Self.binary() {
            let archive = Process(); archive.executableURL = binary; archive.arguments = ["archive", old]
            archive.standardInput = FileHandle.nullDevice; archive.standardOutput = FileHandle.nullDevice; archive.standardError = FileHandle.nullDevice
            try? archive.run()
        }
    }
}
