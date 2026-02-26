import ArgumentParser
import DocScanCore
import Foundation

/// Shared context for benchmark phases, grouping the common dependencies.
struct BenchmarkContext: Sendable {
    let runner: SubprocessRunner
    let engine: BenchmarkEngine
    let pdfSet: BenchmarkPDFSet
    let configuration: Configuration
    let timeoutSeconds: TimeInterval
}

struct BenchmarkCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "benchmark",
        abstract: "Evaluate VLMs and TextLLMs independently against labeled documents"
    )

    @Argument(help: "Directory containing positive sample PDFs (documents that match the type)")
    var positiveDir: String

    @Argument(help: "Directory containing negative sample PDFs (documents that do NOT match the type)")
    var negativeDir: String

    @Option(name: .shortAndLong, help: "Document type to benchmark")
    var type: DocumentType = .invoice

    @Option(name: .shortAndLong, help: "Path to configuration file")
    var config: String?

    @Option(name: [.long, .customLong("family")], help: "VLM model family (e.g. Qwen3-VL) or a concrete model ID")
    var model: String?

    @Option(name: .long, help: "Maximum number of VLM models to discover (default: 25)")
    var limit: Int = 25

    @Flag(name: .shortAndLong, help: "Enable verbose output")
    var verbose: Bool = false

    func run() async throws {
        guard limit > 0, limit <= 1000 else {
            print("Error: --limit must be between 1 and 1000.")
            throw ExitCode.failure
        }

        let documentType = type
        var configuration = try loadConfiguration()
        configuration.verbose = verbose

        printBenchmarkHeader(configuration, documentType: documentType)

        let engine = prepareEngine(configuration: configuration, documentType: documentType)
        let pdfSet = try enumerateAndValidate(engine: engine)

        let timeout = promptTimeoutSelection()
        let apiToken = try promptHuggingFaceCredentials(configuration: configuration)
        let vlmModels = try await resolveVLMModels(apiToken: apiToken)

        let runner = SubprocessRunner()
        defer { runner.cleanup() }

        let context = BenchmarkContext(
            runner: runner, engine: engine, pdfSet: pdfSet,
            configuration: configuration, timeoutSeconds: timeout
        )

        let vlmResults = try await runPhaseA(context: context, vlmModels: vlmModels)
        let textLLMResults = try await runPhaseB(context: context)

        try promptRecommendation(
            vlmResults: vlmResults, textLLMResults: textLLMResults, configuration: configuration
        )

        cleanupModelCaches(engine: engine, vlmResults: vlmResults, textLLMResults: textLLMResults)
        print()
        print("Benchmark complete.")
    }

    // MARK: - Setup Helpers

    private func prepareEngine(
        configuration: Configuration, documentType: DocumentType
    ) -> BenchmarkEngine {
        BenchmarkEngine(
            configuration: configuration, documentType: documentType
        )
    }

    private func enumerateAndValidate(engine: BenchmarkEngine) throws -> BenchmarkPDFSet {
        let resolvedPositiveDir = PathUtils.resolvePath(positiveDir)
        let resolvedNegativeDir = PathUtils.resolvePath(negativeDir)
        let positivePDFs = try engine.enumeratePDFs(in: resolvedPositiveDir)
        let negativePDFs = try engine.enumeratePDFs(in: resolvedNegativeDir)

        guard !positivePDFs.isEmpty else {
            print("No PDF files found in positive directory: \(resolvedPositiveDir)")
            throw ExitCode.failure
        }
        guard !negativePDFs.isEmpty else {
            print("No PDF files found in negative directory: \(resolvedNegativeDir)")
            throw ExitCode.failure
        }

        print("Found \(positivePDFs.count) positive and \(negativePDFs.count) negative documents")
        print()
        return BenchmarkPDFSet(positivePDFs: positivePDFs, negativePDFs: negativePDFs)
    }

    private func cleanupModelCaches(
        engine: BenchmarkEngine,
        vlmResults: [VLMBenchmarkResult],
        textLLMResults: [TextLLMBenchmarkResult]
    ) {
        printBenchmarkPhaseHeader("Cleanup", title: "Model Cache Cleanup")
        let bestVLM = vlmResults.filter { !$0.isDisqualified }
            .max { lhs, rhs in
                lhs.totalScore * rhs.maxScore < rhs.totalScore * lhs.maxScore
                    || (lhs.totalScore * rhs.maxScore == rhs.totalScore * lhs.maxScore
                        && lhs.elapsedSeconds > rhs.elapsedSeconds)
            }?.modelName
        let bestTextLLM = textLLMResults.filter { !$0.isDisqualified }
            .max { lhs, rhs in
                lhs.totalScore * rhs.maxScore < rhs.totalScore * lhs.maxScore
                    || (lhs.totalScore * rhs.maxScore == rhs.totalScore * lhs.maxScore
                        && lhs.elapsedSeconds > rhs.elapsedSeconds)
            }?.modelName

        engine.cleanupBenchmarkedModels(modelNames: vlmResults.map(\.modelName), keepModel: bestVLM)
        engine.cleanupBenchmarkedModels(modelNames: textLLMResults.map(\.modelName), keepModel: bestTextLLM)
    }

    // MARK: - Helpers

    private func loadConfiguration() throws -> Configuration {
        try CLIHelpers.loadConfiguration(configPath: config)
    }

    private func printBenchmarkHeader(_ configuration: Configuration, documentType: DocumentType) {
        print("DocScan Independent Model Benchmark")
        print("====================================")
        print("Document type: \(documentType.displayName)")
        print("Current VLM: \(configuration.modelName)")
        print("Current TextLLM: \(configuration.textModelName)")
        print()
    }

    func printBenchmarkPhaseHeader(_ phase: String, title: String) {
        print()
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("Phase \(phase): \(title)")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print()
    }

    private func promptTimeoutSelection() -> TimeInterval {
        guard let choice = TerminalUtils.menu(
            "Select per-model inference timeout:",
            options: [
                "10 seconds (strict)",
                "30 seconds (recommended)",
                "60 seconds (lenient)",
            ]
        ) else {
            print("Using default: 30 seconds")
            return 30
        }

        let timeouts: [TimeInterval] = [10, 30, 60]
        let selected = timeouts[choice]
        print("Timeout set to \(Int(selected)) seconds per inference.")
        print()
        return selected
    }

    private func promptHuggingFaceCredentials(configuration: Configuration) throws -> String? {
        // Check Keychain
        let account = configuration.benchmark.huggingFaceUsername ?? "default"
        if let stored = try KeychainManager.retrieveToken(forAccount: account) {
            if verbose {
                print("Found existing Hugging Face token in Keychain.")
            }
            return stored
        }

        // Not critical — gated models will be annotated but may fail without a token
        return nil
    }

    // MARK: - Subprocess Worker Helpers

    /// Run a subprocess worker and extract the phase-specific result, or return a disqualified result.
    func runWorker<Result>(
        runner: SubprocessRunner,
        input: BenchmarkWorkerInput,
        modelName: String,
        extractResult: (BenchmarkWorkerOutput) -> Result?,
        makeDisqualified: (String, String) -> Result
    ) async -> Result {
        do {
            let subprocessResult = try await runner.run(input: input)
            switch subprocessResult {
            case let .success(output):
                return extractResult(output) ?? makeDisqualified(
                    modelName, "Worker produced no result"
                )
            case let .crashed(exitCode, signal):
                let detail = signal.map { "signal \($0)" } ?? "exit code \(exitCode)"
                return makeDisqualified(modelName, "Worker crashed (\(detail))")
            case let .decodingFailed(message):
                return makeDisqualified(modelName, message)
            }
        } catch {
            return makeDisqualified(
                modelName, "Failed to spawn worker: \(error.localizedDescription)"
            )
        }
    }

    /// Print a benchmark result summary line (works for any BenchmarkResultProtocol)
    func printBenchmarkResult(_ result: some BenchmarkResultProtocol) {
        if result.isDisqualified {
            print("    DISQUALIFIED: \(result.disqualificationReason ?? "Unknown")")
        } else {
            let scoreStr = String(format: "%.1f%%", result.score * 100)
            let points = "\(result.totalScore)/\(result.maxScore)"
            let time = String(format: "%.1fs", result.elapsedSeconds)
            print("    Score: \(scoreStr) (\(points)) in \(time)")
        }
        print()
    }
}
