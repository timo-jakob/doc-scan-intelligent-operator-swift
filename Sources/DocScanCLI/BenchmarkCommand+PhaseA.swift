import DocScanCore
import Foundation

// MARK: - Phase A: VLM Categorization Benchmark

extension BenchmarkCommand {
    /// Phase A: Run each VLM model against all documents for categorization scoring.
    /// Each model runs in a subprocess so that MLX fatal errors are contained.
    func runPhaseA( // swiftlint:disable:this function_parameter_count
        runner: SubprocessRunner,
        engine: BenchmarkEngine,
        pdfSet: BenchmarkPDFSet,
        vlmModels: [String],
        configuration: Configuration,
        timeoutSeconds: TimeInterval
    ) async throws -> [VLMBenchmarkResult] {
        printBenchmarkPhaseHeader("A", title: "VLM Categorization Benchmark")
        print("Evaluating \(vlmModels.count) VLM model(s)")
        print("Documents: \(pdfSet.positivePDFs.count) positive, \(pdfSet.negativePDFs.count) negative")
        print("Timeout: \(Int(timeoutSeconds))s per inference")
        print()
        var results: [VLMBenchmarkResult] = []

        for (index, modelName) in vlmModels.enumerated() {
            print("[\(index + 1)/\(vlmModels.count)] \(modelName)")

            var workerConfig = configuration
            workerConfig.verbose = verbose
            let input = BenchmarkWorkerInput(
                phase: .vlm,
                modelName: modelName,
                pdfSet: pdfSet,
                timeoutSeconds: timeoutSeconds,
                documentType: engine.documentType,
                configuration: workerConfig
            )

            let result: VLMBenchmarkResult = await runWorker(
                runner: runner, input: input, modelName: modelName,
                extractResult: { $0.vlmResult },
                makeDisqualified: VLMBenchmarkResult.disqualified
            )
            printBenchmarkResult(result)
            results.append(result)
        }

        print(TerminalUtils.formatVLMLeaderboard(results: results))
        print()
        return results
    }
}
