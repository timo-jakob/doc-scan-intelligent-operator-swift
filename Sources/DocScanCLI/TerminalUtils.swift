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

        let widths = ColumnWidths(
            rank: rankWidth, vlm: vlmWidth, text: textWidth,
            accuracy: accWidth, precision: precWidth, recall: recWidth,
            f1Score: f1Width, status: statusWidth
        )

        var lines: [String] = []

        // Header
        let headerRow = RowData(
            rank: "#", vlm: "VLM Model", text: "Text Model",
            accuracy: "Accuracy", precision: "Precision", recall: "Recall",
            f1Score: "F1", status: "Status"
        )
        let header = formatRow(headerRow, widths: widths)
        lines.append(header)
        lines.append(String(repeating: "─", count: header.count))

        // Rows
        for (index, row) in results.enumerated() {
            let rowData = RowData(
                rank: "\(index + 1)",
                vlm: row.vlmModelName,
                text: row.textModelName,
                accuracy: row.isDisqualified ? "  ---" : formatPercent(row.accuracy),
                precision: row.isDisqualified ? "  ---" : formatOptionalPercent(row.precision),
                recall: row.isDisqualified ? "  ---" : formatOptionalPercent(row.recall),
                f1Score: row.isDisqualified ? "  ---" : formatOptionalPercent(row.f1Score),
                status: row.isDisqualified ? "[DISQUALIFIED]" : "OK"
            )
            lines.append(formatRow(rowData, widths: widths))
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
        guard let val = value else { return "  N/A" }
        return formatPercent(val)
    }

    /// Column widths for table formatting
    struct ColumnWidths {
        let rank: Int
        let vlm: Int
        let text: Int
        let accuracy: Int
        let precision: Int
        let recall: Int
        let f1Score: Int
        let status: Int
    }

    /// A single row of cell values for table formatting
    struct RowData {
        let rank: String
        let vlm: String
        let text: String
        let accuracy: String
        let precision: String
        let recall: String
        let f1Score: String
        let status: String
    }

    private static func formatRow(_ row: RowData, widths: ColumnWidths) -> String {
        let rankCol = row.rank.padding(toLength: widths.rank, withPad: " ", startingAt: 0)
        let vlmCol = row.vlm.padding(toLength: widths.vlm, withPad: " ", startingAt: 0)
        let textCol = row.text.padding(toLength: widths.text, withPad: " ", startingAt: 0)
        let accCol = row.accuracy.leftPadded(toLength: widths.accuracy)
        let precCol = row.precision.leftPadded(toLength: widths.precision)
        let recCol = row.recall.leftPadded(toLength: widths.recall)
        let f1Col = row.f1Score.leftPadded(toLength: widths.f1Score)
        let statusCol = row.status.padding(toLength: widths.status, withPad: " ", startingAt: 0)
        return "\(rankCol) \(vlmCol) \(textCol) \(accCol) \(precCol) \(recCol) \(f1Col) \(statusCol)"
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
