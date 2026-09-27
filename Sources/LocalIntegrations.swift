import Foundation

/// Optional local integrations. Commands are argument arrays, never shell strings.
/// No private script, dashboard or record path is embedded in the app.
enum LocalIntegrations {
    enum Command: String {
        case agentStatus = "agentStatusCommand"
        case agentDashboard = "agentDashboardCommand"
        case agentErrorCapture = "agentErrorCaptureCommand"
        case usageSummary = "usageSummaryCommand"
    }
    struct Result { let exitCode: Int32; let output: String; var succeeded: Bool { exitCode == 0 } }
    struct Status { let ok: Bool; let summary: String }
    struct UsageTotals { let totalUSD: Double; let conductorUSD: Double }
    struct LimitShare {
        let commandPercent: Double
        let jevPercent: Double
        let fiveHour: Double
        let week: Double?
        let resets: Date?
        let commandUSD: Double
        let percentPerDollar: Double
    }
    static func command(_ name: Command) -> [String]? {
        guard let args = UserDefaults.standard.stringArray(forKey: name.rawValue),
              let executable = args.first, !executable.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return [NSString(string: executable).expandingTildeInPath] + Array(args.dropFirst())
    }
    static func configured(_ name: Command) -> Bool { command(name) != nil }
    static var dashboardURL: URL? {
        guard let path = UserDefaults.standard.string(forKey: "agentDashboardPath"), !path.isEmpty else { return nil }
        return URL(fileURLWithPath: NSString(string: path).expandingTildeInPath)
    }
    static func run(_ name: Command, extraArguments: [String] = []) async -> Result? {
        guard let args = command(name), let executable = args.first else { return nil }
        return await Task.detached(priority: .utility) {
            guard FileManager.default.isExecutableFile(atPath: executable) else { return Result(exitCode: -1, output: "The configured integration executable was not found.") }
            let task = Process(), pipe = Pipe()
            task.executableURL = URL(fileURLWithPath: executable)
            task.arguments = Array(args.dropFirst()) + extraArguments
            task.currentDirectoryURL = FileManager.default.homeDirectoryForCurrentUser
            task.standardInput = FileHandle.nullDevice
            task.standardOutput = pipe; task.standardError = pipe
            do { try task.run() }
            catch { return Result(exitCode: -1, output: error.localizedDescription) }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            task.waitUntilExit()
            return Result(exitCode: task.terminationStatus, output: String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines))
        }.value
    }
    static func status(from result: Result) -> Status? {
        guard result.succeeded, let data = result.output.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let ok = object["ok"] as? Bool else { return nil }
        let russian = (UserDefaults.standard.string(forKey: "speechLocale") ?? "en-US").hasPrefix("ru")
        let summary = object[russian ? "summary_ru" : "summary_en"] as? String
            ?? object["summary"] as? String ?? object["summary_ru"] as? String ?? ""
        let first = (object["problems"] as? [String])?.first
        return Status(ok: ok, summary: [summary, first].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ": "))
    }
    static func captureAgentError(_ report: [String: String], heard: String) async -> Result? {
        var args = ["--error", report["error"] ?? heard, "--correction", report["correction"] ?? heard, "--heard", heard]
        if let session = report["session"], !session.isEmpty, session != "null" { args += ["--session", session] }
        if let words = report["agent_words"], !words.isEmpty, words != "null" { args += ["--agent-words", words] }
        return await run(.agentErrorCapture, extraArguments: args)
    }
    static func usageTotals(from result: Result) -> UsageTotals? {
        guard result.succeeded, let data = result.output.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let total = object["total_usd"] as? Double,
              let conductor = (object["conductor_usd"] ?? object["jev_voice_usd"]) as? Double,
              total.isFinite, conductor.isFinite, total >= 0, conductor >= 0 else { return nil }
        return UsageTotals(totalUSD: total, conductorUSD: conductor)
    }
    /// Attribution is an estimate, never the account's authoritative usage measurement.
    static func limitShare(totals: UsageTotals, commandUSD: Double, fiveHour: Double, week: Double?, resets: Date, previousRate: Double?) -> LimitShare? {
        guard commandUSD.isFinite, commandUSD >= 0, fiveHour.isFinite, fiveHour >= 0 else { return nil }
        let rate = fiveHour >= 0.10 && totals.totalUSD > 1 ? fiveHour * 100 / totals.totalUSD : previousRate
        guard let rate, rate.isFinite, rate >= 0 else { return nil }
        return LimitShare(commandPercent: commandUSD * rate, jevPercent: (totals.conductorUSD + commandUSD) * rate,
                          fiveHour: fiveHour * 100, week: week.map { $0 * 100 }, resets: resets,
                          commandUSD: commandUSD, percentPerDollar: rate)
    }
}
