import Foundation

public struct CheckReport: Codable, Sendable {
    public var date: Date
    public var appVersion: String
    public var mouseModel: String
    public var outcomes: [StepOutcome]

    public init(date: Date, appVersion: String, mouseModel: String, outcomes: [StepOutcome]) {
        self.date = date
        self.appVersion = appVersion
        self.mouseModel = mouseModel
        self.outcomes = outcomes
    }

    /// The report as Markdown, ready to commit to docs/superpowers/notes/.
    public func markdown() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        var lines = [
            "# MouseBar hardware check",
            "",
            "- Date: \(formatter.string(from: date))",
            "- App version: \(appVersion)",
            "- Mouse: \(mouseModel)",
            "",
            "| Step | Result | Detail |",
            "|---|---|---|",
        ]
        for outcome in outcomes {
            let detail = outcome.detail.replacingOccurrences(of: "|", with: "/")
            lines.append("| \(outcome.step.title) | \(outcome.result.word) | \(detail) |")
        }
        let raw = outcomes.filter { $0.rawHex != nil }
        if !raw.isEmpty {
            lines += ["", "## Raw replies", ""]
            for outcome in raw {
                lines.append("- \(outcome.step.title): `\(outcome.rawHex ?? "")`")
            }
        }
        let measured = outcomes.filter { !$0.measurements.isEmpty }
        if !measured.isEmpty {
            lines += ["", "## Measurements", ""]
            for outcome in measured {
                let parts = outcome.measurements
                    .sorted { $0.key < $1.key }
                    .map { "\($0.key) = \(String(format: "%.1f", $0.value))" }
                lines.append("- \(outcome.step.title): \(parts.joined(separator: ", "))")
            }
        }
        return lines.joined(separator: "\n") + "\n"
    }
}
