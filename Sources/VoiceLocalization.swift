import Foundation

/// Loads optional Russian command phrases independently of the macOS UI language.
enum VoiceLocalization {
    private static var russianBundle: Bundle? {
        guard let path = Bundle.main.path(forResource: "ru", ofType: "lproj") else { return nil }
        return Bundle(path: path)
    }

    static func value(_ key: String, fallback: String = "") -> String {
        let language = UserDefaults.standard.string(forKey: "speechLocale") ?? "en-US"
        guard language.lowercased().hasPrefix("ru"), let bundle = russianBundle else { return fallback }
        return bundle.localizedString(forKey: key, value: fallback, table: nil)
    }

    static func words(_ key: String, fallback: String = "") -> [String] {
        value(key, fallback: fallback).split(separator: "|").map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        }.filter { !$0.isEmpty }
    }

    static func aliases(_ key: String) -> [String: String] {
        var result: [String: String] = [:]
        for entry in words(key) {
            let fields = entry.split(separator: "=", maxSplits: 1).map(String.init)
            if fields.count == 2 { result[fields[0]] = fields[1] }
        }
        return result
    }
}
