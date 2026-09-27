import Foundation

enum CommandJournalTests {
    static func run() {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("conductor-journal-test-" + UUID().uuidString)
        let domain = "conductor.journal.tests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain); try? FileManager.default.removeItem(at: root) }
        var enabled = false
        let files = DiagnosticFiles(directory: root, enabled: { enabled })
        let journal = CommandJournal(files: files, defaults: defaults)
        let password = "quote\"line\nsecret"
        let entry: [String: Any] = ["epoch": 5.0, "time": "test", "command": "enter " + password,
            "outcome": "failed", "answer": "code 4 8 1 5 1 6",
            "check": [["ok": Optional<Bool>.none as Any]],
            "error": "could not enter " + password, "problems": ["code 481516 failed"],
            "missing_tools": ["tool for " + password], "agent_errors": [["error": password, "correction": "481516"]]]
        journal.record(entry, secrets: [password, "481516"])
        files.flush()
        precondition(!FileManager.default.fileExists(atPath: root.path), "Opt-out must create no command files")
        precondition(journal.summary().contains("[redacted]") && !journal.summary().contains(password),
                     "In-memory model-switch context works without writing secrets")

        enabled = true
        journal.record(entry, secrets: [password, "481516"])
        files.flush()
        for name in ["journal.jsonl", "problems.jsonl", "tool-wishes.jsonl", "agent-errors.jsonl"] {
            let file = root.appendingPathComponent(name)
            let contents = try! String(contentsOf: file, encoding: .utf8)
            precondition(!contents.contains("secret") && !contents.contains("481516") && !contents.contains("4 8 1 5 1 6"))
            for line in contents.split(separator: "\n") {
                precondition((try? JSONSerialization.jsonObject(with: Data(line.utf8))) != nil,
                             "Redaction must preserve valid JSON, including escaped secrets and optional verdicts")
            }
            let mode = (try! FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as! NSNumber).intValue
            precondition(mode & 0o077 == 0, "Command diagnostics are private to the local user")
        }
        precondition(!CommandJournal(files: files, defaults: defaults).summary().isEmpty, "Opted-in recent history restores")

        enabled = false
        journal.reset(at: Date(timeIntervalSince1970: 10))
        precondition(journal.summary().isEmpty)
        journal.record(entry, secrets: [password, "481516"])
        precondition(journal.summary().isEmpty, "A late pre-reset command cannot repopulate current context")
        enabled = true
        precondition(CommandJournal(files: files, defaults: defaults).summary().isEmpty,
                     "Reset while diagnostics are off must still prevent old context returning")
        journal.record(["epoch": 20.0, "command": "new request", "answer": "new result", "outcome": "done"], secrets: [])
        files.flush()
        let restored = CommandJournal(files: files, defaults: defaults).summary()
        precondition(restored.contains("new request") && !restored.contains("enter"))
        print("PASS: opt-in command journal, in-memory model-switch context, JSON secret redaction, private files, error/wish records, persistent reset boundary.")
    }
}
