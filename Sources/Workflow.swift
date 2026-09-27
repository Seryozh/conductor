import Foundation

enum VoiceControl: Equatable {
    case cancelTask, retry, status, stopListening, resetConversation
    case switchModel(String)

    private static var switchVerbs: Set<String> {
        Set(["switch", "use", "change", "model"] + VoiceLocalization.words("commands.switchVerbs"))
    }
    private static var leadIns: Set<String> {
        Set(["please", "hey", "okay", "jev"] + VoiceLocalization.words("commands.leadIns"))
    }
    private static var resetPhrases: [String] {
        ["reset", "start over"] + VoiceLocalization.words("commands.reset")
    }

    static func modelSwitch(_ words: [String]) -> VoiceControl? {
        var words = words
        while let first = words.first, leadIns.contains(first) { words.removeFirst() }
        let ignored = ["agent", "session", "tell", "write", "ask"] + VoiceLocalization.words("commands.switchIgnoreTokens")
        guard (2...6).contains(words.count), let first = words.first, switchVerbs.contains(first),
              !words.contains(where: { word in ignored.contains { word.hasPrefix($0) } }),
              let choice = BrainChoice.named(in: Array(words.dropFirst())) else { return nil }
        return .switchModel(choice.id)
    }

    static func parse(_ text: String) -> VoiceControl? {
        let command = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        let words = command.split { !$0.isLetter }.map(String.init)
        if words.count <= 5, resetPhrases.contains(where: { command.contains($0) }) { return .resetConversation }
        if let change = modelSwitch(words) { return change }
        let localized = VoiceLocalization.words("commands.controls")
        let phrases: [(String, VoiceControl)] = [
            ("cancel task|cancel that|cancel|stop now|stop", .cancelTask),
            ("try again|retry|retry task", .retry),
            ("status|what are you doing|what is happening", .status),
            ("stop listening|turn off the mic|turn off microphone|microphone off|mic off", .stopListening),
        ]
        for (items, result) in phrases where items.split(separator: "|").contains(where: { command == $0 }) {
            return result
        }
        for entry in localized {
            let fields = entry.split(separator: "=", maxSplits: 1).map(String.init)
            guard fields.count == 2, let result = control(fields[1]), command == fields[0] else { continue }
            return result
        }
        return nil
    }

    private static func control(_ value: String) -> VoiceControl? {
        switch value {
        case "cancel": return .cancelTask
        case "retry": return .retry
        case "status": return .status
        case "stop": return .stopListening
        default: return nil
        }
    }
}

struct WorkflowTrace {
    var actions: [String] = []
    var signatures: [String: Int] = [:]
    var lastFailure: String?
    var modelCalls = 0
    static let maximumActions = 48
    static let maximumCalls = 80
    mutating func record(action: String, signature: String) throws {
        actions.append(action)
        signatures[signature, default: 0] += 1
        guard actions.count <= Self.maximumActions else { throw VoiceError.message("Stopped after 48 actions. Say a smaller follow-up request to continue.") }
    }
    func repetitionCount(_ signature: String) -> Int { signatures[signature, default: 0] }
}
