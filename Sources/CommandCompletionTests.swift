import Foundation

enum CommandCompletionTests {
    static func run() {
        func review(_ completion: inout CommandCompletion, ok: Bool? = nil,
                    acts: Bool = false, next: Bool = false, action: String = "click Next",
                    state: String = "page one", cancelled: Bool = false) -> CommandCompletion.Decision {
            completion.review(ok: ok, hasActions: acts, announcesNextStep: next,
                              action: action, observation: state, cancelled: cancelled)
        }

        var longTask = CommandCompletion()
        for step in 0..<50 {
            precondition(review(&longTask, acts: true, state: "page \(step)") == .continueActions,
                         "Pending actions must still execute after the fourth check")
        }
        precondition(review(&longTask, ok: true) == .completed)

        var verdicts = CommandCompletion()
        precondition(review(&verdicts) == .unverified, "Missing ok cannot imply completion")
        precondition(review(&verdicts, ok: false) == .failed)
        precondition(review(&verdicts, ok: false, acts: true) == .failed,
                     "An explicit failure cannot run contradictory action fields")
        precondition(review(&verdicts, ok: true) == .completed)
        precondition(review(&verdicts, ok: true, next: true) == .unverified,
                     "A promised next step contradicts a final success claim")
        precondition(review(&verdicts, ok: true, acts: true) == .continueActions,
                     "Unperformed fields take precedence over a premature success claim")

        var stalled = CommandCompletion()
        precondition(review(&stalled, acts: true) == .continueActions)
        precondition(review(&stalled, acts: true) == .noProgress)
        precondition(review(&stalled, acts: true, action: "use keyboard Next") == .continueActions,
                     "An alternative recovery action remains available")
        precondition(review(&stalled, acts: true, state: "page two") == .continueActions,
                     "The same action remains available after observed progress")
        precondition(review(&stalled, acts: true) == .noProgress,
                     "Returning to an earlier state must not hide an action cycle")

        var cancelled = CommandCompletion()
        precondition(review(&cancelled, acts: true, cancelled: true) == .cancelled)
        precondition(review(&cancelled, ok: true, cancelled: true) == .cancelled,
                     "A late verdict cannot overwrite cancellation with Done")
        precondition(review(&cancelled, acts: true) == .continueActions,
                     "Cancelled replies must not record unperformed actions")
        precondition(CommandCompletion.fingerprint(Data("one".utf8)) != CommandCompletion.fingerprint(Data("two".utf8)))
        print("PASS: whole-command completion, 50 progressing rounds, missing/false/true verdicts, repeated-state recovery, cycles, cancellation.")
    }
}
