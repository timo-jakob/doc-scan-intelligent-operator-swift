import DocScanCore
import Foundation

// MARK: - Phase A: VLM Categorization Benchmark

extension BenchmarkCommand {
    /// Phase A: Run each VLM model against all documents for categorization scoring.
    /// Each model runs in a subprocess so that MLX fatal errors are contained.
    func runPhaseA(
        engine: BenchmarkEngine,
        positivePDFs: [String],
        negativePDFs: [String],
        configuration: Configuration,
        timeoutSeconds: TimeInterval
    ) async throws -> [VLMBenchmarkResult] {
        printBenchmarkPhaseHeader("A", title: "VLM Categorization Benchmark")

        let vlmModels = configuration.benchmark.vlmModels ?? DefaultModelLists.vlmModels
        print("Evaluating \(vlmModels.count) VLM model(s)")
        print("Documents: \(positivePDFs.count) positive, \(negativePDFs.count) negative")
        print("Timeout: \(Int(timeoutSeconds))s per inference")
        print()

        let runner = SubprocessRunner()
        var results: [VLMBenchmarkResult] = []

        for (index, modelName) in vlmModels.enumerated() {
            print("[\(index + 1)/\(vlmModels.count)] \(modelName)")

            let input = BenchmarkWorkerInput(
                phase: .vlm,
                modelName: modelName,
                positivePDFs: positivePDFs,
                negativePDFs: negativePDFs,
                timeoutSeconds: timeoutSeconds,
                documentType: engine.documentType,
                configuration: configuration,
                verbose: verbose
            )

            let result = await runVLMWorker(runner: runner, input: input, modelName: modelName)
            printVLMResult(result)
            results.append(result)
        }

        print(TerminalUtils.formatVLMLeaderboard(results: results))
        print()
        return results
    }

    private func runVLMWorker(
        runner: SubprocessRunner,
        input: BenchmarkWorkerInput,
        modelName: String
    ) async -> VLMBenchmarkResult {
        do {
            let subprocessResult = try await runner.run(input: input)
            switch subprocessResult {
            case let .success(output):
                return output.vlmResult ?? .disqualified(
                    modelName: modelName, reason: "Worker produced no VLM result"
                )
            case let .crashed(exitCode, signal):
                let detail = signal != nil
                    ? "signal \(signal!)" : "exit code \(exitCode)"
                return .disqualified(
                    modelName: modelName, reason: "Worker crashed (\(detail))"
                )
            case let .decodingFailed(message):
                return .disqualified(modelName: modelName, reason: message)
            }
        } catch {
            return .disqualified(
                modelName: modelName,
                reason: "Failed to spawn worker: \(error.localizedDescription)"
            )
        }
    }

    private func printVLMResult(_ result: VLMBenchmarkResult) {
        if result.isDisqualified {
            print("  DISQUALIFIED: \(result.disqualificationReason ?? "Unknown")")
        } else {
            let scoreStr = String(format: "%.1f%%", result.score * 100)
            let points = "\(result.totalScore)/\(result.maxScore)"
            let time = String(format: "%.1fs", result.elapsedSeconds)
            print("  Score: \(scoreStr) (\(points)) in \(time)")
        }
        print()
    }
}
