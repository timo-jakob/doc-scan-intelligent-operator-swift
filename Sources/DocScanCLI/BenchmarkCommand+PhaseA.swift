import DocScanCore
import Foundation

// MARK: - Phase A: VLM Categorization Benchmark

extension BenchmarkCommand {
    /// Phase A: Run each VLM model against all documents for categorization scoring
    func runPhaseA(
        engine: BenchmarkEngine,
        positivePDFs: [String],
        negativePDFs: [String],
        configuration: Configuration,
        timeoutSeconds: TimeInterval
    ) async throws -> [VLMBenchmarkResult] {
        printBenchmarkPhaseHeader("A", title: "VLM Categorization Benchmark")

        let vlmModels = configuration.benchmarkVLMModels ?? DefaultModelLists.vlmModels
        print("Evaluating \(vlmModels.count) VLM model(s)")
        print("Documents: \(positivePDFs.count) positive, \(negativePDFs.count) negative")
        print("Timeout: \(Int(timeoutSeconds))s per inference")
        print()

        let vlmFactory = DefaultVLMOnlyFactory()
        var results: [VLMBenchmarkResult] = []

        for (index, modelName) in vlmModels.enumerated() {
            print("[\(index + 1)/\(vlmModels.count)] \(modelName)")

            let result = await engine.benchmarkVLM(
                modelName: modelName,
                positivePDFs: positivePDFs,
                negativePDFs: negativePDFs,
                timeoutSeconds: timeoutSeconds,
                vlmFactory: vlmFactory
            )

            if result.isDisqualified {
                print("  DISQUALIFIED: \(result.disqualificationReason ?? "Unknown")")
            } else {
                let scoreStr = String(format: "%.1f%%", result.score * 100)
                let points = "\(result.totalScore)/\(result.maxScore)"
                let time = String(format: "%.1fs", result.elapsedSeconds)
                print("  Score: \(scoreStr) (\(points)) in \(time)")
            }
            print()

            results.append(result)
        }

        // Display VLM leaderboard
        print(TerminalUtils.formatVLMLeaderboard(results: results))
        print()

        return results
    }
}
