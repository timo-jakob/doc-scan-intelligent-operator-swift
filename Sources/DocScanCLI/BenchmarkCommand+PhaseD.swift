import DocScanCore
import Foundation

// MARK: - Phase D: Leaderboards and Configuration

extension BenchmarkCommand {
    /// Phase D: Display leaderboards and optionally update config
    func runPhaseD(
        results: [ModelPairResult],
        configuration: Configuration,
        configPath: String?
    ) throws {
        printBenchmarkPhaseHeader("D", title: "Results & Leaderboards")

        let rows = results.map { ModelPairResultRow(from: $0) }

        // Full metrics table
        print(TerminalUtils.formatMetricsTable(rows))
        print()

        printLeaderboards(rows)
        try promptConfigUpdate(results: results, configuration: configuration, configPath: configPath)
    }

    private func printLeaderboards(_ rows: [ModelPairResultRow]) {
        let boards: [(String, (ModelPairResultRow) -> Double?)] = [
            ("Leaderboard: Accuracy", { $0.accuracy }),
            ("Leaderboard: F1 Score", { $0.f1Score }),
            ("Leaderboard: Precision", { $0.precision }),
            ("Leaderboard: Recall", { $0.recall }),
        ]
        for (title, sortBy) in boards {
            print(TerminalUtils.formatLeaderboard(title: title, results: rows, sortBy: sortBy))
            print()
        }
    }

    private func promptConfigUpdate(
        results: [ModelPairResult],
        configuration: Configuration,
        configPath: String?
    ) throws {
        let best = results
            .filter { !$0.isDisqualified }
            .max(by: { $0.metrics.accuracy < $1.metrics.accuracy })

        guard let bestPair = best else {
            print("No qualifying model pairs to recommend.")
            return
        }

        let isCurrent = bestPair.vlmModelName == configuration.modelName
            && bestPair.textModelName == configuration.textModelName

        if isCurrent {
            print("Your current model pair is already the best performer!")
            return
        }

        print("Best performing pair:")
        print("  VLM:  \(bestPair.vlmModelName)")
        print("  Text: \(bestPair.textModelName)")
        print("  Accuracy: \(String(format: "%.1f%%", bestPair.metrics.accuracy * 100))")
        print()

        if TerminalUtils.confirm("Update your configuration to use this pair?") {
            var newConfig = configuration
            newConfig.modelName = bestPair.vlmModelName
            newConfig.textModelName = bestPair.textModelName

            if let path = configPath {
                try newConfig.save(to: path)
                print("Configuration saved to \(path)")
            } else {
                let defaultPath = "docscan-config.yaml"
                try newConfig.save(to: defaultPath)
                print("Configuration saved to \(defaultPath)")
            }
        }
    }
}
