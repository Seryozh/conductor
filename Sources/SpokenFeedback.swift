import AVFoundation

@MainActor final class SpokenFeedback: NSObject, AVSpeechSynthesizerDelegate {
    private let synthesizer = AVSpeechSynthesizer()
    var onSpeakingChanged: ((Bool) -> Void)?
    private var generation = 0
    override init() { super.init(); synthesizer.delegate = self }
    func say(_ text: String) {
        generation += 1
        synthesizer.stopSpeaking(at: .immediate)
        onSpeakingChanged?(true)
        let utterance = AVSpeechUtterance(string: text)
        // Speak in the selected recognition language. English is the first-run default.
        let language = UserDefaults.standard.string(forKey: "speechLocale") ?? "en-US"
        let prefix = String(language.prefix(2))
        utterance.voice = AVSpeechSynthesisVoice.speechVoices().filter { $0.language.hasPrefix(prefix) }
            .max { $0.quality.rawValue < $1.quality.rawValue } ?? AVSpeechSynthesisVoice(language: language)
        utterance.rate = 0.53
        DebugLog.write("SPEAK start (\(text.count) chars, voice \(utterance.voice?.name ?? "default"))")
        synthesizer.speak(utterance)
    }
    func stop() {
        generation += 1
        synthesizer.stopSpeaking(at: .immediate)
        onSpeakingChanged?(false)
    }
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) { DebugLog.write("SPEAK finished to the end (\(utterance.speechString.count) chars)"); Task { @MainActor [weak self] in self?.resumeAfterTail() } }
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) { DebugLog.write("SPEAK cut off (\(utterance.speechString.count) chars)"); Task { @MainActor [weak self] in self?.resumeAfterTail() } }
    private func resumeAfterTail() {
        let token = generation
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            guard let self, token == self.generation, !self.synthesizer.isSpeaking else { return }
            self.onSpeakingChanged?(false)
        }
    }
}
