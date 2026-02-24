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

        var oldTermios = termios()
        tcgetattr(STDIN_FILENO, &oldTermios)
        defer {
            tcsetattr(STDIN_FILENO, TCSANOW, &oldTermios)
            print() // newline after masked input
        }

        var newTermios = oldTermios
        newTermios.c_lflag &= ~UInt(ECHO)
        tcsetattr(STDIN_FILENO, TCSANOW, &newTermios)

        return readLine()?.trimmingCharacters(in: .whitespaces)
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

    // MARK: - Generic Leaderboard

    /// Format a leaderboard from benchmark results, ranked by score descending then time ascending.
    /// - Parameters:
    ///   - title: Leaderboard title
    ///   - results: All results (qualifying and disqualified)
    ///   - headerSuffix: Column headers after the common "Score%  Points" columns
    ///   - rowFormatter: Closure that formats the type-specific columns for a qualifying result
    static func formatLeaderboard<T: BenchmarkResultProtocol>(
        title: String,
        results: [T],
        headerSuffix: String,
        rowFormatter: (T) -> String
    ) -> String {
        var lines: [String] = []
        lines.append(title)
        lines.append(String(repeating: "═", count: title.count))

        let qualifying = results.rankedByScore()

        if qualifying.isEmpty {
            lines.append("  No qualifying results.")
        } else {
            let modelWidth = max(12, qualifying.map(\.modelName.count).max() ?? 12)
            let header = "  #  \("Model".padding(toLength: modelWidth, withPad: " ", startingAt: 0))"
                + "  Score%  Points  \(headerSuffix)   Time  Status"
            lines.append(header)
            lines.append("  " + String(repeating: "─", count: header.count - 2))

            for (index, result) in qualifying.enumerated() {
                let rankStr = String(index + 1).leftPadded(toLength: 3)
                let model = result.modelName.padding(toLength: modelWidth, withPad: " ", startingAt: 0)
                let score = formatPercent(result.score)
                let points = "\(result.totalScore)/\(result.maxScore)".leftPadded(toLength: 6)
                let extra = rowFormatter(result)
                let time = formatTime(result.elapsedSeconds)
                lines.append("  \(rankStr)  \(model)  \(score)  \(points)  \(extra)  \(time)  OK")
            }
        }

        let disqualified = results.filter(\.isDisqualified)
        if !disqualified.isEmpty {
            lines.append("")
            for result in disqualified {
                let reason = result.disqualificationReason ?? "Unknown"
                lines.append("  DQ  \(result.modelName)  (\(reason))")
            }
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - VLM Leaderboard

    /// Format a VLM leaderboard sorted by score (desc), then by time (asc) for ties
    static func formatVLMLeaderboard(results: [VLMBenchmarkResult]) -> String {
        formatLeaderboard(
            title: "VLM Leaderboard: Categorization",
            results: results,
            headerSuffix: "TP  TN  FP  FN"
        ) { result in
            let truePos = String(result.truePositives).leftPadded(toLength: 3)
            let trueNeg = String(result.trueNegatives).leftPadded(toLength: 3)
            let falsePos = String(result.falsePositives).leftPadded(toLength: 3)
            let falseNeg = String(result.falseNegatives).leftPadded(toLength: 3)
            return "\(truePos) \(trueNeg) \(falsePos) \(falseNeg)"
        }
    }

    // MARK: - TextLLM Leaderboard

    /// Format a TextLLM leaderboard sorted by score (desc), then by time (asc) for ties
    static func formatTextLLMLeaderboard(results: [TextLLMBenchmarkResult]) -> String {
        formatLeaderboard(
            title: "TextLLM Leaderboard: Categorization + Extraction",
            results: results,
            headerSuffix: "2s  1s  0s"
        ) { result in
            let twos = String(result.fullyCorrectCount).leftPadded(toLength: 3)
            let ones = String(result.partiallyCorrectCount).leftPadded(toLength: 3)
            let zeros = String(result.fullyWrongCount).leftPadded(toLength: 3)
            return "\(twos) \(ones) \(zeros)"
        }
    }

    // MARK: - Private Helpers

    static func formatPercent(_ value: Double) -> String {
        String(format: "%5.1f%%", value * 100)
    }

    static func formatTime(_ seconds: TimeInterval) -> String {
        String(format: "%5.1fs", seconds)
    }
}

private extension String {
    func leftPadded(toLength length: Int) -> String {
        if count >= length { return self }
        return String(repeating: " ", count: length - count) + self
    }
}
