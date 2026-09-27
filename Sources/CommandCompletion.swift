import Foundation
import CryptoKit

/// A result check describes the whole command. An absent verdict is not success,
/// and having work left never becomes success because the command took many rounds.
struct CommandCompletion {
    enum Decision: Equatable {
        case continueActions
        case completed
        case failed
        case unverified
        case noProgress
        case cancelled
    }

    private var attemptedStates = Set<String>()

    mutating func review(ok: Bool?, hasActions: Bool, announcesNextStep: Bool,
                         action: String, observation: String, cancelled: Bool) -> Decision {
        guard !cancelled else { return .cancelled }
        if ok == false { return .failed }
        if hasActions {
            // A different action can recover from a failed attempt; the same action
            // is also allowed after an observable change. Repeating both is a loop.
            let state = Self.fingerprint(Data((observation + "\u{0}" + action).utf8))
            guard attemptedStates.insert(state).inserted else { return .noProgress }
            return .continueActions
        }
        return ok == true && !announcesNextStep ? .completed : .unverified
    }

    static func fingerprint(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
