import DocScanCore
import Foundation

// MARK: - Phase D: Leaderboards and Configuration

extension BenchmarkCommand {
    /// Phase D: Display leaderboards and optionally update config.
    /// Returns the final selected model pair (VLM, TextLLM) after any config update.
    @discardableResult
    func runPhaseD(
        results: [ModelPairResult],
        configuration: Configuration,
        configPath: String?
    ) throws -> (vlm: String, text: String) {
        printBenchmarkPhaseHeader("D", title: "Results & Leaderboards")

        let rows = results.map { ModelPairResultRow(from: $0) }

        // Full metrics table
        print(TerminalUtils.formatMetricsTable(rows))
        print()

        // Single leaderboard sorted by score
        print(TerminalUtils.formatLeaderboard(title: "Leaderboard: Score", results: rows))
        print()

        return try promptConfigUpdate(
            results: results, configuration: configuration, configPath: configPath
        )
    }

    private func promptConfigUpdate(
        results: [ModelPairResult],
        configuration: Configuration,
        configPath: String?
    ) throws -> (vlm: String, text: String) {
        let currentPair = (vlm: configuration.modelName, text: configuration.textModelName)

        let qualifying = results
            .filter { !$0.isDisqualified }
            .sorted { $0.metrics.score > $1.metrics.score }

        guard !qualifying.isEmpty else {
            print("No qualifying model pairs to recommend.")
            return currentPair
        }

        // Build menu options: each pair with its score, mark current
        var options: [String] = qualifying.map { pair in
            let scoreStr = String(format: "%.1f%%", pair.metrics.score * 100)
            let points = "\(pair.metrics.totalScore)/\(pair.metrics.maxScore)"
            let current = (pair.vlmModelName == configuration.modelName
                && pair.textModelName == configuration.textModelName) ? " (current)" : ""
            return "\(pair.vlmModelName) + \(pair.textModelName)  \(scoreStr) (\(points) pts)\(current)"
        }
        options.append("Keep current configuration")

        guard let choice = TerminalUtils.menu(
            "Select a model pair to use as your default:",
            options: options
        ) else {
            return currentPair
        }

        // Last option = keep current
        guard choice < qualifying.count else {
            print("Keeping current configuration.")
            return currentPair
        }

        let selected = qualifying[choice]
        let isCurrent = selected.vlmModelName == configuration.modelName
            && selected.textModelName == configuration.textModelName

        if isCurrent {
            print("That is already your current configuration.")
            return currentPair
        }

        var newConfig = configuration
        newConfig.modelName = selected.vlmModelName
        newConfig.textModelName = selected.textModelName

        if let path = configPath {
            try newConfig.save(to: path)
            print("Configuration saved to \(path)")
        } else {
            let defaultPath = Configuration.defaultConfigPath
            try newConfig.save(to: defaultPath)
            print("Configuration saved to \(defaultPath)")
        }

        return (vlm: selected.vlmModelName, text: selected.textModelName)
    }
}
