import Foundation
import AppKit
import Darwin

// Isolated transport fixtures, never launch the app, call a model, change credentials,
// inspect another application's UI, or use the user's Application Support directory.
enum VoiceError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
}
enum DebugLog { static func write(_ text: String) {} }
enum KeyStore { static func save(_ text: String) throws { preconditionFailure("A transport test tried to save a real key") } }

@main struct LocalControlTests {
    @MainActor static func main() {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("conductor-control-tests-" + UUID().uuidString)
        var busy = false
        var executions = 0
        let server = LocalControlServer(root: root)
        do {
            try server.start(runtime: { ["busy": busy, "model": "fixture", "key_configured": false,
                                        "accessibility_granted": false, "microphone_granted": false, "speech_granted": false] }, submit: { command in
                guard !busy else { return LocalCommandSubmission(state: "rejected", error: "Busy fixture") }
                executions += 1
                if command == "reject" { return LocalCommandSubmission(state: "rejected", error: "Rejected fixture") }
                if command == "local" { return LocalCommandSubmission(state: "done") }
                busy = true
                if command != "pending" {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                        busy = false; server.finish(outcome: command == "fail" ? "failed" : "done", error: command == "fail" ? "Expected failure" : nil)
                    }
                }
                return LocalCommandSubmission(state: "running")
            })
        } catch { fatalError("Could not start fixture server: \(error)") }
        Task {
            let initial = LocalControlCLI.status(root: root)
            precondition(initial.0["running"] as? Bool == true && initial.0["model"] as? String == "fixture")
            precondition(initial.0["key_configured"] as? Bool == false)
            let lockContender = LocalControlServer(root: root)
            do { try lockContender.start(runtime: { [:] }, submit: { _ in .init(state: "done") }); preconditionFailure("Duplicate server accepted") } catch { }
            let id = UUID().uuidString
            let accepted = await Task.detached { LocalControlCLI.command("fixture", id: id, root: root) }.value
            precondition(accepted.0["state"] as? String == "running", "Acceptance was incorrectly called completion")
            let rejection = await Task.detached { LocalControlCLI.command("second while busy", root: root) }.value
            precondition(rejection.0["state"] as? String == "rejected" && rejection.1 == 1)
            try? await Task.sleep(nanoseconds: 800_000_000)
            let completed = LocalControlCLI.status(id: id, root: root)
            precondition(completed.0["state"] as? String == "done" && completed.1 == 0)
            let duplicate = await Task.detached { LocalControlCLI.command("must not execute again", id: id, root: root) }.value
            precondition(duplicate.0["state"] as? String == "done" && executions == 1)
            let rejected = await Task.detached { LocalControlCLI.command("reject", root: root) }.value
            precondition(rejected.0["state"] as? String == "rejected" && rejected.1 == 1)
            let failed = await Task.detached { LocalControlCLI.command("fail", wait: 3, root: root) }.value
            precondition(failed.0["state"] as? String == "failed" && failed.1 == 1)
            let local = await Task.detached { LocalControlCLI.command("local", root: root) }.value
            precondition(local.0["state"] as? String == "done" && local.1 == 0)
            let pendingID = UUID().uuidString
            let timed = await Task.detached { LocalControlCLI.command("pending", id: pendingID, wait: 0.3, root: root) }.value
            precondition(timed.0["state"] as? String == "running" && timed.0["wait_expired"] as? Bool == true && timed.1 == 3)
            precondition(LocalControlCLI.status(id: "../../bad", root: root).1 == 2)
            precondition(LocalControlCLI.command("", root: root).1 == 2)
            precondition(LocalControlCLI.command(String(repeating: "x", count: 4001), root: root).1 == 2)
            let unknown = LocalControlCLI.status(id: UUID().uuidString, root: root)
            precondition(unknown.0["state"] as? String == "unknown" && unknown.1 == 1)
            for outcome in ["error", "failed", "unrecognized"] { precondition(LocalControlFiles.terminalState(outcome: outcome, error: nil) == "failed") }
            precondition(LocalControlFiles.terminalState(outcome: "done", error: "error") == "failed")
            precondition(LocalControlFiles.terminalState(outcome: "answered", error: nil) == "answered")
            precondition(LocalControlFiles.terminalState(outcome: "cancelled", error: nil) == "cancelled")
            let receipt = root.appendingPathComponent("results/\(id).json")
            let rootMode = try! FileManager.default.attributesOfItem(atPath: root.path)[.posixPermissions] as! NSNumber
            let receiptMode = try! FileManager.default.attributesOfItem(atPath: receipt.path)[.posixPermissions] as! NSNumber
            precondition(rootMode.intValue == 0o700 && receiptMode.intValue == 0o600)
            precondition((try! FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("requests").path)).isEmpty)
            server.stop()
            let stopped = LocalControlCLI.status(id: pendingID, root: root)
            precondition(stopped.0["state"] as? String == "interrupted" && stopped.1 == 1)
            precondition(LocalControlCLI.status(root: root).0["running"] as? Bool == false)
            let offline = LocalControlCLI.command("must not run", root: root)
            precondition(offline.0["state"] as? String == "rejected" && offline.1 == 1)
            let priorID = UUID().uuidString
            try! LocalControlFiles.write(["id": priorID, "state": "running", "updated_at": Date().timeIntervalSince1970], to: root.appendingPathComponent("results/\(priorID).json"))
            let replacement = LocalControlServer(root: root)
            try! replacement.start(runtime: { [:] }, submit: { _ in preconditionFailure("A restart reran a command") })
            precondition(LocalControlCLI.status(id: priorID, root: root).0["state"] as? String == "interrupted")
            replacement.stop()
            try? FileManager.default.removeItem(at: root)
            print("PASS: runtime status, acknowledgement vs completion, busy rejection, duplicate IDs, failures, immediate local commands, wait timeout, invalid and unknown IDs, private file modes, no command history, shutdown, restart, and missing app.")
            exit(0)
        }
        RunLoop.main.add(Timer(timeInterval: 60, repeats: true) { _ in }, forMode: .default)
        CFRunLoopRun()
    }
}
