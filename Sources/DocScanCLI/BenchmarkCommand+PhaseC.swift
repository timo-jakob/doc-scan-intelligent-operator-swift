import DocScanCore
import Foundation

// MARK: - Phase C: Benchmark Model Pairs

extension BenchmarkCommand {
    /// Phase C: Benchmark each discovered model pair
    func runPhaseC(
        engine: BenchmarkEngine,
        pairs: [ModelPair],
        pdfPaths: [String],
        groundTruths: [String: GroundTruth],
        timeoutSeconds: TimeInterval
    ) async throws -> [ModelPairResult] {
        printBenchmarkPhaseHeader("C", title: "Benchmarking Model Pairs")

        var results: [ModelPairResult] = []

        for (index, pair) in pairs.enumerated() {
            print("[\(index + 1)/\(pairs.count)] Benchmarking:")
            print("  VLM:  \(pair.vlmModelName)")
            print("  Text: \(pair.textModelName)")

            let result = try await engine.benchmarkModelPair(
                pair,
                pdfPaths: pdfPaths,
                groundTruths: groundTruths,
                timeoutSeconds: timeoutSeconds
            )

            if result.isDisqualified {
                print("  ❌ DISQUALIFIED: \(result.disqualificationReason ?? "Unknown")")
            } else {
                let acc = String(format: "%.1f%%", result.metrics.accuracy * 100)
                let correct = result.documentResults.filter(\.isFullyCorrect).count
                let total = result.documentResults.count
                print("  ✅ Accuracy: \(acc) (\(correct)/\(total) correct)")
            }
            print()

            results.append(result)
        }

        return results
    }
}
