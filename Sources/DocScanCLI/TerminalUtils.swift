import Darwin
import DocScanCore
import Foundation

/// Terminal interaction utilities for CLI commands
enum TerminalUtils {
    /// Prompt the user for input and return their response
    static func prompt(_ message: String) -> String? {
        print(message, terminator: " ")
        return readLine()?.trimmingCharacters(in: .whitespaces)
    }

    /// Prompt for input with masked characters (for passwords/tokens)
    static func promptMasked(_ message: String) -> String? {
        print(message, terminator: " ")

        // Disable echo
        var oldTermios = termios()
        tcgetattr(STDIN_FILENO, &oldTermios)
        var newTermios = oldTermios
        newTermios.c_lflag &= ~UInt(ECHO)
        tcsetattr(STDIN_FILENO, TCSANOW, &newTermios)

        let input = readLine()

        // Restore echo
        tcsetattr(STDIN_FILENO, TCSANOW, &oldTermios)
        print() // newline after masked input

        return input?.trimmingCharacters(in: .whitespaces)
    }

    /// Present a numbered menu and return the selected index (0-based)
    static func menu(_ title: String, options: [String]) -> Int? {
        print(title)
        for (index, option) in options.enumerated() {
            print("  [\(index + 1)] \(option)")
        }
        print()
        guard let input = prompt("Enter your choice (1-\(options.count)):"),
              let choice = Int(input),
              choice >= 1, choice <= options.count
        else {
            return nil
        }
        return choice - 1
    }

    /// Ask a yes/no confirmation question
    static func confirm(_ message: String) -> Bool {
        guard let input = prompt("\(message) [y/N]:") else {
            return false
        }
        return ["y", "yes"].contains(input.lowercased())
    }

    // MARK: - Table Formatting

    /// Format a metrics comparison table for display
    static func formatMetricsTable(_ results: [ModelPairResultRow]) -> String {
        guard !results.isEmpty else { return "No results to display." }

        // Column widths
        let rankWidth = 4
        let vlmWidth = max(10, results.map(\.vlmModelName.count).max() ?? 10)
        let textWidth = max(12, results.map(\.textModelName.count).max() ?? 12)
        let accWidth = 8
        let precWidth = 9
        let recWidth = 8
        let f1Width = 8
        let statusWidth = 14

        var lines: [String] = []

        // Header
        let header = formatRow(
            rank: "#",
            vlm: "VLM Model",
            text: "Text Model",
            accuracy: "Accuracy",
            precision: "Precision",
            recall: "Recall",
            f1: "F1",
            status: "Status",
            widths: (rankWidth, vlmWidth, textWidth, accWidth, precWidth, recWidth, f1Width, statusWidth)
        )
        lines.append(header)
        lines.append(String(repeating: "─", count: header.count))

        // Rows
        for (index, row) in results.enumerated() {
            let rank = "\(index + 1)"
            let status = row.isDisqualified ? "[DISQUALIFIED]" : "OK"
            let accuracy = row.isDisqualified ? "  ---" : formatPercent(row.accuracy)
            let precision = row.isDisqualified ? "  ---" : formatOptionalPercent(row.precision)
            let recall = row.isDisqualified ? "  ---" : formatOptionalPercent(row.recall)
            let f1 = row.isDisqualified ? "  ---" : formatOptionalPercent(row.f1Score)

            lines.append(formatRow(
                rank: rank,
                vlm: row.vlmModelName,
                text: row.textModelName,
                accuracy: accuracy,
                precision: precision,
                recall: recall,
                f1: f1,
                status: status,
                widths: (rankWidth, vlmWidth, textWidth, accWidth, precWidth, recWidth, f1Width, statusWidth)
            ))
        }

        return lines.joined(separator: "\n")
    }

    /// Format a leaderboard sorted by a specific metric
    static func formatLeaderboard(
        title: String,
        results: [ModelPairResultRow],
        sortBy: (ModelPairResultRow) -> Double?
    ) -> String {
        var lines: [String] = []
        lines.append(title)
        lines.append(String(repeating: "═", count: title.count))

        // Sort: non-disqualified first, then by metric descending, nil values last
        let sorted = results
            .filter { !$0.isDisqualified }
            .sorted { lhs, rhs in
                let lVal = sortBy(lhs) ?? -1
                let rVal = sortBy(rhs) ?? -1
                return lVal > rVal
            }

        if sorted.isEmpty {
            lines.append("  No qualifying results.")
            return lines.joined(separator: "\n")
        }

        for (index, row) in sorted.enumerated() {
            let value = sortBy(row).map { formatPercent($0) } ?? "N/A"
            lines.append("  \(index + 1). \(row.vlmModelName) + \(row.textModelName)  \(value)")
        }

        // Add disqualified entries
        let disqualified = results.filter(\.isDisqualified)
        if !disqualified.isEmpty {
            lines.append("")
            for row in disqualified {
                let reason = row.disqualificationReason ?? "Unknown"
                lines.append("  DQ  \(row.vlmModelName) + \(row.textModelName)  (\(reason))")
            }
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - Private Helpers

    private static func formatPercent(_ value: Double) -> String {
        String(format: "%5.1f%%", value * 100)
    }

    private static func formatOptionalPercent(_ value: Double?) -> String {
        guard let v = value else { return "  N/A" }
        return formatPercent(v)
    }

    private static func formatRow(
        rank: String,
        vlm: String,
        text: String,
        accuracy: String,
        precision: String,
        recall: String,
        f1: String,
        status: String,
        widths: (Int, Int, Int, Int, Int, Int, Int, Int)
    ) -> String {
        let r = rank.padding(toLength: widths.0, withPad: " ", startingAt: 0)
        let v = vlm.padding(toLength: widths.1, withPad: " ", startingAt: 0)
        let t = text.padding(toLength: widths.2, withPad: " ", startingAt: 0)
        let a = accuracy.leftPadded(toLength: widths.3)
        let p = precision.leftPadded(toLength: widths.4)
        let rc = recall.leftPadded(toLength: widths.5)
        let f = f1.leftPadded(toLength: widths.6)
        let s = status.padding(toLength: widths.7, withPad: " ", startingAt: 0)
        return "\(r) \(v) \(t) \(a) \(p) \(rc) \(f) \(s)"
    }
}

/// Simplified row data for table formatting
struct ModelPairResultRow {
    let vlmModelName: String
    let textModelName: String
    let accuracy: Double
    let precision: Double?
    let recall: Double?
    let f1Score: Double?
    let isDisqualified: Bool
    let disqualificationReason: String?

    init(from result: ModelPairResult) {
        vlmModelName = result.vlmModelName
        textModelName = result.textModelName
        accuracy = result.metrics.accuracy
        precision = result.metrics.precision
        recall = result.metrics.recall
        f1Score = result.metrics.f1Score
        isDisqualified = result.isDisqualified
        disqualificationReason = result.disqualificationReason
    }

    init(
        vlmModelName: String,
        textModelName: String,
        accuracy: Double,
        precision: Double? = nil,
        recall: Double? = nil,
        f1Score: Double? = nil,
        isDisqualified: Bool = false,
        disqualificationReason: String? = nil
    ) {
        self.vlmModelName = vlmModelName
        self.textModelName = textModelName
        self.accuracy = accuracy
        self.precision = precision
        self.recall = recall
        self.f1Score = f1Score
        self.isDisqualified = isDisqualified
        self.disqualificationReason = disqualificationReason
    }
}

private extension String {
    func leftPadded(toLength length: Int) -> String {
        if count >= length { return self }
        return String(repeating: " ", count: length - count) + self
    }
}
