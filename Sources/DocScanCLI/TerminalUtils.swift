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
        let scoreWidth = 8
        let pointsWidth = 8
        let breakdownWidth = 11
        let statusWidth = 14

        let widths = ColumnWidths(
            rank: rankWidth, vlm: vlmWidth, text: textWidth,
            score: scoreWidth, points: pointsWidth,
            breakdown: breakdownWidth, status: statusWidth
        )

        var lines: [String] = []

        // Header
        let headerRow = RowData(
            rank: "#", vlm: "VLM Model", text: "Text Model",
            score: "Score", points: "Points",
            breakdown: "2s/1s/0s", status: "Status"
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
                score: row.isDisqualified ? "  ---" : formatPercent(row.score),
                points: row.isDisqualified ? "  ---" : "\(row.totalScore)/\(row.maxScore)",
                breakdown: row.isDisqualified
                    ? "  ---"
                    : "\(row.fullyCorrectCount)/\(row.partiallyCorrectCount)/\(row.fullyWrongCount)",
                status: row.isDisqualified ? "[DISQUALIFIED]" : "OK"
            )
            lines.append(formatRow(rowData, widths: widths))
        }

        return lines.joined(separator: "\n")
    }

    /// Format a leaderboard sorted by score
    static func formatLeaderboard(
        title: String,
        results: [ModelPairResultRow]
    ) -> String {
        var lines: [String] = []
        lines.append(title)
        lines.append(String(repeating: "═", count: title.count))

        // Sort: non-disqualified first, then by score descending
        let sorted = results
            .filter { !$0.isDisqualified }
            .sorted { $0.score > $1.score }

        if sorted.isEmpty {
            lines.append("  No qualifying results.")
            return lines.joined(separator: "\n")
        }

        for (index, row) in sorted.enumerated() {
            let value = formatPercent(row.score)
            let points = "\(row.totalScore)/\(row.maxScore)"
            lines.append("  \(index + 1). \(row.vlmModelName) + \(row.textModelName)  \(value)  (\(points) pts)")
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

    /// Column widths for table formatting
    struct ColumnWidths {
        let rank: Int
        let vlm: Int
        let text: Int
        let score: Int
        let points: Int
        let breakdown: Int
        let status: Int
    }

    /// A single row of cell values for table formatting
    struct RowData {
        let rank: String
        let vlm: String
        let text: String
        let score: String
        let points: String
        let breakdown: String
        let status: String
    }

    private static func formatRow(_ row: RowData, widths: ColumnWidths) -> String {
        let rankCol = row.rank.padding(toLength: widths.rank, withPad: " ", startingAt: 0)
        let vlmCol = row.vlm.padding(toLength: widths.vlm, withPad: " ", startingAt: 0)
        let textCol = row.text.padding(toLength: widths.text, withPad: " ", startingAt: 0)
        let scoreCol = row.score.leftPadded(toLength: widths.score)
        let pointsCol = row.points.leftPadded(toLength: widths.points)
        let breakdownCol = row.breakdown.leftPadded(toLength: widths.breakdown)
        let statusCol = row.status.padding(toLength: widths.status, withPad: " ", startingAt: 0)
        return "\(rankCol) \(vlmCol) \(textCol) \(scoreCol) \(pointsCol) \(breakdownCol) \(statusCol)"
    }
}

/// Score breakdown metrics for a benchmark result row
struct ScoreBreakdown {
    let totalScore: Int
    let maxScore: Int
    let fullyCorrectCount: Int
    let partiallyCorrectCount: Int
    let fullyWrongCount: Int

    init(
        totalScore: Int = 0,
        maxScore: Int = 0,
        fullyCorrectCount: Int = 0,
        partiallyCorrectCount: Int = 0,
        fullyWrongCount: Int = 0
    ) {
        self.totalScore = totalScore
        self.maxScore = maxScore
        self.fullyCorrectCount = fullyCorrectCount
        self.partiallyCorrectCount = partiallyCorrectCount
        self.fullyWrongCount = fullyWrongCount
    }
}

/// Simplified row data for table formatting
struct ModelPairResultRow {
    let vlmModelName: String
    let textModelName: String
    let score: Double
    let breakdown: ScoreBreakdown
    let isDisqualified: Bool
    let disqualificationReason: String?

    var totalScore: Int {
        breakdown.totalScore
    }

    var maxScore: Int {
        breakdown.maxScore
    }

    var fullyCorrectCount: Int {
        breakdown.fullyCorrectCount
    }

    var partiallyCorrectCount: Int {
        breakdown.partiallyCorrectCount
    }

    var fullyWrongCount: Int {
        breakdown.fullyWrongCount
    }

    init(from result: ModelPairResult) {
        vlmModelName = result.vlmModelName
        textModelName = result.textModelName
        score = result.metrics.score
        breakdown = ScoreBreakdown(
            totalScore: result.metrics.totalScore,
            maxScore: result.metrics.maxScore,
            fullyCorrectCount: result.metrics.fullyCorrectCount,
            partiallyCorrectCount: result.metrics.partiallyCorrectCount,
            fullyWrongCount: result.metrics.fullyWrongCount
        )
        isDisqualified = result.isDisqualified
        disqualificationReason = result.disqualificationReason
    }

    init(
        vlmModelName: String,
        textModelName: String,
        score: Double,
        breakdown: ScoreBreakdown = ScoreBreakdown(),
        isDisqualified: Bool = false,
        disqualificationReason: String? = nil
    ) {
        self.vlmModelName = vlmModelName
        self.textModelName = textModelName
        self.score = score
        self.breakdown = breakdown
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
