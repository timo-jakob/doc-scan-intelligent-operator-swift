import ArgumentParser
import DocScanCore
import Foundation
import MLX

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

        // Set MLX memory budget (same as parent)
        let memoryBudget = Int(Double(ProcessInfo.processInfo.physicalMemory) * 0.8)
        Memory.memoryLimit = memoryBudget

        let engine = BenchmarkEngine(
            configuration: workerInput.configuration,
            documentType: workerInput.documentType,
            verbose: workerInput.verbose
        )

        let workerOutput: BenchmarkWorkerOutput = switch workerInput.phase {
        case .vlm:
            await runVLMBenchmark(engine: engine, input: workerInput)
        case .textLLM:
            await runTextLLMBenchmark(engine: engine, input: workerInput)
        }

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
            positivePDFs: workerInput.positivePDFs,
            negativePDFs: workerInput.negativePDFs,
            timeoutSeconds: workerInput.timeoutSeconds,
            vlmFactory: vlmFactory
        )
        return BenchmarkWorkerOutput(vlmResult: result)
    }

    private func runTextLLMBenchmark(
        engine: BenchmarkEngine,
        input workerInput: BenchmarkWorkerInput
    ) async -> BenchmarkWorkerOutput {
        let ocrTexts = workerInput.ocrTexts ?? [:]
        let groundTruths = workerInput.groundTruths ?? [:]

        let context = TextLLMBenchmarkContext(
            ocrTexts: ocrTexts,
            groundTruths: groundTruths,
            timeoutSeconds: workerInput.timeoutSeconds,
            textLLMFactory: DefaultTextLLMOnlyFactory()
        )

        let result = await engine.benchmarkTextLLM(
            modelName: workerInput.modelName,
            positivePDFs: workerInput.positivePDFs,
            negativePDFs: workerInput.negativePDFs,
            context: context
        )
        return BenchmarkWorkerOutput(textLLMResult: result)
    }
}
