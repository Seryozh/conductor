import AppKit
import AVFoundation

@MainActor enum SpeechRuntimeTest {
    /// The replay runs in real time. A windowless test process is eligible for App Nap, and
    /// a plain 160-second asyncAfter may fire up to 16 s late (10% leeway): on 2026-09-28 the
    /// key release landed 3.2 s late, after the replay ended, so nothing was submitted.
    private static var activity: NSObjectProtocol?
    private static var release: DispatchSourceTimer?
    static func run(_ url: URL, releaseDuringRotation: Bool) throws {
        activity = ProcessInfo.processInfo.beginActivity(options: [.userInitiated, .latencyCritical], reason: "Real-time speech replay test")
        let previous = UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)
        UserDefaults.standard.setVolatileDomain(["whisperEnabled": false, "speechLocale": "en-US"], forName: UserDefaults.argumentDomain)
        let engine = SpeechEngine()
        engine.manualEndpoint = true
        let file = try AVAudioFile(forReading: url)
        let seconds = Double(file.length) / file.processingFormat.sampleRate
        var rotations = 0, released = false
        var first = "", longest = 0
        let started = Date()
        engine.onTranscript = { text in
            if first.isEmpty && !text.isEmpty { first = text }
            longest = max(longest, text.split(separator: " ").count)
        }
        engine.onDiagnostic = { message in
            fputs(String(format: "%7.2f ", Date().timeIntervalSince(started)) + message + "\n", stderr); fflush(stderr)
            if message.hasPrefix("begin request") { rotations += 1 }
            if releaseDuringRotation, !released, message.hasPrefix("finish request"), message.contains("submit=false") {
                released = true
                DispatchQueue.main.async { engine.finishNow() }
            }
        }
        engine.onError = { message in print("FAIL: " + message); exit(1) }
        engine.onInterrupted = { text, message in print("FAIL: interrupted after \(text.count) preserved characters: " + message); exit(1) }
        engine.onFinished = { text in
            let words = text.split(separator: " ").count
            let passed = releaseDuringRotation ? released && words > 20 : seconds > 120 && words > 180 && text.lowercased().contains("beginning") && text.lowercased().contains("final sentence")
            let report: [String: Any] = ["passed": passed, "seconds": seconds, "rotations": rotations, "release_during_rotation": releaseDuringRotation, "first_partial": first, "maximum_partial_words": longest, "submitted_words": words, "transcript": text]
            print(String(data: try! JSONSerialization.data(withJSONObject: report, options: [.sortedKeys]), encoding: .utf8)!)
            engine.cancel()
            UserDefaults.standard.setVolatileDomain(previous, forName: UserDefaults.argumentDomain)
            exit(passed ? 0 : 1)
        }
        try engine.replay(url) { print("FAIL: recording ended without the expected submission; rotations=\(rotations), maximum_partial_words=\(longest), first_partial=\(first)"); exit(1) }
        if !releaseDuringRotation {
            let timer = DispatchSource.makeTimerSource(queue: .main)
            timer.schedule(deadline: .now() + seconds + 0.12, leeway: .milliseconds(10))
            timer.setEventHandler {
                fputs(String(format: "%7.2f key released\n", Date().timeIntervalSince(started)), stderr)
                engine.finishNow()
            }
            timer.resume()
            release = timer
        }
    }
}
