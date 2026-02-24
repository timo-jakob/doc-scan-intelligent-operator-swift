import ArgumentParser
import DocScanCore
import Foundation

/// Hidden subcommand spawned by `BenchmarkCommand` to isolate each model benchmark in its own
/// process. If the model triggers a `fatalError` in MLX's C++ layer, only this worker dies —
/// the parent marks it DISQUALIFIED and continues.
struct BenchmarkWorkerCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "benchmark-worker",
        abstract: "Run a single model benchmark in an isolated subprocess",
        shouldDisplay: false
    )

    @Option(name: .long, help: "Path to input JSON file")
    var input: String

    @Option(name: .long, help: "Path to write output JSON file")
    var output: String

    func run() async throws {
        let inputData = try Data(contentsOf: URL(fileURLWithPath: input))
        let workerInput = try JSONDecoder().decode(BenchmarkWorkerInput.self, from: inputData)

        do {
            let workerOutput = try await executeBenchmark(workerInput: workerInput)
            try writeOutput(workerOutput)
        } catch {
            // Best-effort: write a disqualified result so the parent gets a meaningful
            // error message. If this also fails, the process exits non-zero and the
            // parent handles it as a crash.
            let reason = "Worker error: \(error.localizedDescription)"
            let errorOutput = workerInput.makeDisqualifiedOutput(reason: reason)
            try? writeOutput(errorOutput)
        }
    }

    private func executeBenchmark(
        workerInput: BenchmarkWorkerInput
    ) async throws -> BenchmarkWorkerOutput {
        BenchmarkEngine.configureMLXMemoryBudget()

        let engine = BenchmarkEngine(
            configuration: workerInput.configuration,
            documentType: workerInput.documentType
        )

        return switch workerInput.phase {
        case .vlm:
            await runVLMBenchmark(engine: engine, input: workerInput)
        case .textLLM:
            await runTextLLMBenchmark(engine: engine, input: workerInput)
        }
    }

    private func writeOutput(_ workerOutput: BenchmarkWorkerOutput) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let outputData = try encoder.encode(workerOutput)
        try outputData.write(to: URL(fileURLWithPath: output))
    }

    private func runVLMBenchmark(
        engine: BenchmarkEngine,
        input workerInput: BenchmarkWorkerInput
    ) async -> BenchmarkWorkerOutput {
        let vlmFactory = DefaultVLMOnlyFactory()
        let result = await engine.benchmarkVLM(
            modelName: workerInput.modelName,
            positivePDFs: workerInput.pdfSet.positivePDFs,
            negativePDFs: workerInput.pdfSet.negativePDFs,
            timeoutSeconds: workerInput.timeoutSeconds,
            vlmFactory: vlmFactory
        )
        return .vlm(result)
    }

    private func runTextLLMBenchmark(
        engine: BenchmarkEngine,
        input workerInput: BenchmarkWorkerInput
    ) async -> BenchmarkWorkerOutput {
        let textLLMData = workerInput.textLLMData
        let context = TextLLMBenchmarkContext(
            ocrTexts: textLLMData?.ocrTexts ?? [:],
            groundTruths: textLLMData?.groundTruths ?? [:],
            timeoutSeconds: workerInput.timeoutSeconds,
            textLLMFactory: DefaultTextLLMOnlyFactory()
        )

        let result = await engine.benchmarkTextLLM(
            modelName: workerInput.modelName,
            positivePDFs: workerInput.pdfSet.positivePDFs,
            negativePDFs: workerInput.pdfSet.negativePDFs,
            context: context
        )
        return .textLLM(result)
    }
}
