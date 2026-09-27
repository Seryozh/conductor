import Foundation

/// Optional instructions chosen by this user, separate from application code.
enum LocalProfile {
    static var instructions: String {
        guard let configured = UserDefaults.standard.string(forKey: "instructionsFilePath"), !configured.isEmpty else { return "" }
        let path = (configured as NSString).expandingTildeInPath
        guard let text = try? String(contentsOfFile: path, encoding: .utf8), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return "" }
        return "\n\nUser-configured local instructions (from the file selected in this Mac's settings):\n" + text
    }
}
