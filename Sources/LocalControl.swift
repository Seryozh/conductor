import Foundation
import AppKit
import Darwin

/// Local, same-user command transport. Private files hold only pending commands and
/// short-lived receipts, independently of opt-in diagnostic logging.
enum LocalControlFiles {
    static var root: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent(Bundle.main.bundleIdentifier ?? "ai.conductor.public", isDirectory: true)
            .appendingPathComponent("LocalControl", isDirectory: true)
    }
    static func prepare(_ root: URL) throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        for url in [root, root.appendingPathComponent("requests"), root.appendingPathComponent("results")] {
            if !FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
            }
            let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
            guard attrs[.type] as? FileAttributeType == .typeDirectory,
                  attrs[.ownerAccountID] as? NSNumber == NSNumber(value: getuid()) else {
                throw VoiceError.message("Local control directory is not a directory owned by this user.")
            }
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
        }
    }
    static func read(_ url: URL) -> [String: Any]? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              attrs[.type] as? FileAttributeType == .typeRegular,
              attrs[.ownerAccountID] as? NSNumber == NSNumber(value: getuid()),
              let size = attrs[.size] as? NSNumber, size.intValue <= 65_536,
              let data = try? Data(contentsOf: url),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return object
    }
    static func write(_ object: [String: Any], to url: URL) throws {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        // Atomic replacement never exposes partial JSON. The containing directory is 0700.
        try data.write(to: url, options: [.atomic])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
    static func validID(_ value: String) -> Bool { UUID(uuidString: value) != nil }
    static func liveState(at root: URL, now: TimeInterval = Date().timeIntervalSince1970) -> [String: Any]? {
        guard let state = read(root.appendingPathComponent("status.json")),
              let updated = state["updated_at"] as? Double, now - updated >= -2, now - updated < 4,
              let pid = state["pid"] as? Int32, kill(pid, 0) == 0,
              state["running"] as? Bool == true else { return nil }
        return state
    }
    static func isTerminal(_ state: String) -> Bool {
        ["done", "answered", "failed", "cancelled", "rejected", "interrupted"].contains(state)
    }
    static func terminalState(outcome: String, error: String?) -> String {
        if error != nil { return "failed" }
        switch outcome {
        case "done", "reset", "reset by the brain": return "done"
        case "answered": return "answered"
        case "cancelled": return "cancelled"
        default: return "failed"
        }
    }
}

struct LocalCommandSubmission {
    let state: String
    var error: String? = nil
}

@MainActor final class LocalControlServer {
    private let root: URL
    private let instance = UUID().uuidString
    private var lockFD: Int32 = -1
    private var timer: Timer?
    private var activeID: String?
    private var submit: ((String) -> LocalCommandSubmission)?
    private var runtime: (() -> [String: Any])?
    private var lastCleanup = Date.distantPast
    private var lastStatusWrite = Date.distantPast
    private var lastStatusData: Data?

    init(root: URL = LocalControlFiles.root) { self.root = root }
    func start(runtime: @escaping () -> [String: Any], submit: @escaping (String) -> LocalCommandSubmission) throws {
        try LocalControlFiles.prepare(root)
        lockFD = open(root.appendingPathComponent("server.lock").path, O_CREAT | O_RDWR | O_NOFOLLOW, 0o600)
        guard lockFD >= 0, flock(lockFD, LOCK_EX | LOCK_NB) == 0 else {
            if lockFD >= 0 { close(lockFD); lockFD = -1 }
            throw VoiceError.message("Another Conductor instance already owns local control.")
        }
        self.runtime = runtime; self.submit = submit
        // A restart cannot resume a previously accepted command or claim it completed.
        for file in (try? FileManager.default.contentsOfDirectory(at: root.appendingPathComponent("results"), includingPropertiesForKeys: nil)) ?? [] {
            guard var result = LocalControlFiles.read(file), let state = result["state"] as? String,
                  !LocalControlFiles.isTerminal(state) else { continue }
            result["state"] = "interrupted"; result["error"] = "Conductor restarted before recording a result."
            result["updated_at"] = Date().timeIntervalSince1970
            try? LocalControlFiles.write(result, to: file)
        }
        tick()
        timer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }
    func stop() {
        timer?.invalidate(); timer = nil
        if activeID != nil { finish(outcome: "interrupted", error: "Conductor quit before recording a result.") }
        if LocalControlFiles.read(root.appendingPathComponent("status.json"))?["instance"] as? String == instance {
            try? FileManager.default.removeItem(at: root.appendingPathComponent("status.json"))
        }
        if lockFD >= 0 { flock(lockFD, LOCK_UN); close(lockFD); lockFD = -1 }
    }
    func finish(outcome: String, error: String?) {
        guard let id = activeID else { return }
        activeID = nil
        receipt(id, state: outcome == "interrupted" ? "interrupted" : LocalControlFiles.terminalState(outcome: outcome, error: error), outcome: outcome, error: error)
    }
    private func receipt(_ id: String, state: String, outcome: String? = nil, error: String? = nil) {
        var object: [String: Any] = ["id": id, "instance": instance, "state": state, "updated_at": Date().timeIntervalSince1970]
        if let outcome { object["outcome"] = outcome }
        if let error { object["error"] = error }
        do { try LocalControlFiles.write(object, to: root.appendingPathComponent("results/\(id).json")) }
        catch { DebugLog.write("LOCAL CONTROL: could not save a command receipt: " + error.localizedDescription) }
    }
    private func tick() {
        var state = runtime?() ?? [:]
        state["running"] = true; state["pid"] = getpid(); state["instance"] = instance
        if let activeID { state["active_command_id"] = activeID }
        let comparable = try? JSONSerialization.data(withJSONObject: state, options: [.sortedKeys])
        if comparable != lastStatusData || Date().timeIntervalSince(lastStatusWrite) >= 1 {
            state["updated_at"] = Date().timeIntervalSince1970
            do {
                try LocalControlFiles.write(state, to: root.appendingPathComponent("status.json"))
                lastStatusData = comparable; lastStatusWrite = Date()
            } catch { }
        }
        let requests = root.appendingPathComponent("requests")
        for file in ((try? FileManager.default.contentsOfDirectory(at: requests, includingPropertiesForKeys: nil)) ?? []).sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            let id = file.deletingPathExtension().lastPathComponent
            guard file.pathExtension == "json", LocalControlFiles.validID(id) else { continue }
            guard let request = LocalControlFiles.read(file) else { continue }
            // Remove the command text before execution; no command history is created here.
            try? FileManager.default.removeItem(at: file)
            if LocalControlFiles.read(root.appendingPathComponent("results/\(id).json")) != nil { continue }
            guard request["instance"] as? String == instance,
                  let created = request["created_at"] as? Double,
                  abs(Date().timeIntervalSince1970 - created) < 10,
                  let command = request["command"] as? String, !command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  command.count <= 4000 else { receipt(id, state: "rejected", error: "Request expired or is invalid. Submit again explicitly."); continue }
            let result = submit?(command) ?? LocalCommandSubmission(state: "rejected", error: "Command handler is unavailable.")
            if result.state == "running" { activeID = id }
            receipt(id, state: result.state, error: result.error)
        }
        if Date().timeIntervalSince(lastCleanup) > 60 {
            lastCleanup = Date()
            for file in (try? FileManager.default.contentsOfDirectory(at: root.appendingPathComponent("results"), includingPropertiesForKeys: nil)) ?? [] {
                guard file.deletingPathExtension().lastPathComponent != activeID,
                      let result = LocalControlFiles.read(file), let updated = result["updated_at"] as? Double,
                      Date().timeIntervalSince1970 - updated > 600 else { continue }
                try? FileManager.default.removeItem(at: file)
            }
        }
    }
}

enum LocalControlCLI {
    static func printJSON(_ value: [String: Any]) {
        if let data = try? JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys]), let text = String(data: data, encoding: .utf8) { print(text) }
    }
    static func status(id: String? = nil, root: URL = LocalControlFiles.root) -> ([String: Any], Int32) {
        let runtime = LocalControlFiles.liveState(at: root)
        guard let id else { return (runtime ?? ["running": false, "error": "No responsive Conductor local-control server."], runtime == nil ? 1 : 0) }
        guard LocalControlFiles.validID(id) else { return (["state": "rejected", "error": "Command ID must be a UUID."], 2) }
        guard var result = LocalControlFiles.read(root.appendingPathComponent("results/\(id).json")) else {
            return (["id": id, "state": "unknown", "running": runtime != nil, "error": "No receipt for this ID. Unknown does not mean failed or safe to repeat."], 1)
        }
        result["running"] = runtime != nil
        if !LocalControlFiles.isTerminal(result["state"] as? String ?? ""), runtime == nil {
            result["state"] = "interrupted"; result["error"] = "The app stopped responding before a final receipt. Effects are unknown."
        }
        return (result, ["failed", "rejected", "cancelled", "interrupted"].contains(result["state"] as? String ?? "") ? 1 : 0)
    }
    static func command(_ text: String, id: String = UUID().uuidString, wait: TimeInterval = 0, root: URL = LocalControlFiles.root) -> ([String: Any], Int32) {
        guard LocalControlFiles.validID(id), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, text.count <= 4000 else {
            return (["state": "rejected", "error": "Give a nonempty command under 4,001 characters and a UUID command ID."], 2)
        }
        if LocalControlFiles.read(root.appendingPathComponent("results/\(id).json")) != nil { return status(id: id, root: root) }
        guard let runtime = LocalControlFiles.liveState(at: root), let instance = runtime["instance"] as? String else {
            return (["id": id, "state": "rejected", "error": "No responsive Conductor. Open the app before submitting a command."], 1)
        }
        do {
            try LocalControlFiles.prepare(root)
            let request: [String: Any] = ["id": id, "instance": instance, "created_at": Date().timeIntervalSince1970, "command": text]
            try LocalControlFiles.write(request, to: root.appendingPathComponent("requests/\(id).json"))
        } catch { return (["id": id, "state": "rejected", "error": error.localizedDescription], 1) }
        let deadline = Date().addingTimeInterval(max(3, wait))
        repeat {
            if let result = LocalControlFiles.read(root.appendingPathComponent("results/\(id).json")) {
                if wait <= 0 || LocalControlFiles.isTerminal(result["state"] as? String ?? "") { return status(id: id, root: root) }
            }
            Thread.sleep(forTimeInterval: 0.1)
        } while Date() < deadline
        var (result, code) = status(id: id, root: root)
        result["wait_expired"] = true
        // A timeout is never completion and never authorizes an automatic retry.
        if !LocalControlFiles.isTerminal(result["state"] as? String ?? "") { code = 3 }
        return (result, code)
    }
    static func storeKey() -> Int32 {
        do {
            if isatty(STDIN_FILENO) != 0 {
                guard let pointer = getpass("API key (hidden, saved only in macOS Keychain): ") else { return 1 }
                defer { memset(pointer, 0, strlen(pointer)) }
                try KeyStore.save(String(cString: pointer))
            } else {
                var data = FileHandle.standardInput.readData(ofLength: 16_385)
                defer { data.resetBytes(in: 0..<data.count) }
                guard data.count <= 16_384, let key = String(data: data, encoding: .utf8) else { throw VoiceError.message("Invalid key input.") }
                try KeyStore.save(key)
            }
            print("Key saved in macOS Keychain. The key was not printed."); return 0
        } catch { print("Could not save the key: " + error.localizedDescription); return 1 }
    }
}
