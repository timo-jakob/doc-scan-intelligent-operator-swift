import ArgumentParser
import DocScanCore
import Foundation
import MLX

struct BenchmarkCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "benchmark",
        abstract: "Evaluate VLMs and TextLLMs independently against labeled documents"
    )

    @Argument(help: "Directory containing positive sample PDFs (documents that match the type)")
    var positiveDir: String

    @Argument(help: "Directory containing negative sample PDFs (documents that do NOT match the type)")
    var negativeDir: String

    @Option(name: .shortAndLong, help: "Document type to benchmark: 'invoice' (default) or 'prescription'")
    var type: String = "invoice"

    @Option(name: .shortAndLong, help: "Path to configuration file")
    var config: String?

    @Flag(name: .shortAndLong, help: "Enable verbose output")
    var verbose: Bool = false

    func run() async throws {
        let memoryBudget = Int(Double(ProcessInfo.processInfo.physicalMemory) * 0.8)
        Memory.memoryLimit = memoryBudget

        let documentType = try parseDocumentType()
        var configuration = try loadConfiguration()
        configuration.verbose = verbose

        printBenchmarkHeader(configuration, documentType: documentType)

        let engine = prepareEngine(configuration: configuration, documentType: documentType)
        let (positivePDFs, negativePDFs) = try enumerateAndValidate(engine: engine)

        let timeout = promptTimeoutSelection()
        let apiToken = try promptHuggingFaceCredentials(configuration: &configuration)
        _ = apiToken

        let vlmResults = try await runPhaseA(
            engine: engine, positivePDFs: positivePDFs, negativePDFs: negativePDFs,
            configuration: configuration, timeoutSeconds: timeout
        )

        let textLLMResults = try await runPhaseB(
            engine: engine, positivePDFs: positivePDFs, negativePDFs: negativePDFs,
            configuration: configuration, timeoutSeconds: timeout
        )

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
            configuration: configuration, documentType: documentType, verbose: verbose
        )
    }

    private func enumerateAndValidate(
        engine: BenchmarkEngine
    ) throws -> (positive: [String], negative: [String]) {
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
        return (positivePDFs, negativePDFs)
    }

    private func cleanupModelCaches(
        engine: BenchmarkEngine,
        vlmResults: [VLMBenchmarkResult],
        textLLMResults: [TextLLMBenchmarkResult]
    ) {
        printBenchmarkPhaseHeader("Cleanup", title: "Model Cache Cleanup")
        let bestVLM = vlmResults.filter { !$0.isDisqualified }
            .sorted { $0.score > $1.score }.first?.modelName
        let bestTextLLM = textLLMResults.filter { !$0.isDisqualified }
            .sorted { $0.score > $1.score }.first?.modelName

        engine.cleanupBenchmarkedModels(modelNames: vlmResults.map(\.modelName), keepModel: bestVLM)
        engine.cleanupBenchmarkedModels(modelNames: textLLMResults.map(\.modelName), keepModel: bestTextLLM)
    }

    // MARK: - Helpers

    private func parseDocumentType() throws -> DocumentType {
        switch type.lowercased() {
        case "invoice": return .invoice
        case "prescription": return .prescription
        default:
            print("Invalid document type: '\(type)'")
            print("Valid types: invoice, prescription")
            throw ExitCode.failure
        }
    }

    private func loadConfiguration() throws -> Configuration {
        if let configPath = config {
            return try Configuration.load(from: configPath)
        }
        let defaultPath = Configuration.defaultConfigPath
        if FileManager.default.fileExists(atPath: defaultPath) {
            return try Configuration.load(from: defaultPath)
        }
        return Configuration.defaultConfiguration
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

    private func promptHuggingFaceCredentials(configuration: inout Configuration) throws -> String? {
        // Check Keychain
        let account = configuration.huggingFaceUsername ?? "default"
        if let stored = try KeychainManager.retrieveToken(forAccount: account) {
            if verbose {
                print("Found existing Hugging Face token in Keychain.")
            }
            return stored
        }

        // Not critical for benchmark — models are from hardcoded lists
        return nil
    }

    /// Prompt to update config with best VLM + best TextLLM
    private func promptRecommendation(
        vlmResults: [VLMBenchmarkResult],
        textLLMResults: [TextLLMBenchmarkResult],
        configuration: Configuration
    ) throws {
        printBenchmarkPhaseHeader("Recommendation", title: "Best Models")

        let bestVLM = bestQualifyingResult(from: vlmResults)
        let bestTextLLM = bestQualifyingResult(from: textLLMResults)

        printBestModel(label: "VLM", result: bestVLM)
        printBestModel(label: "TextLLM", result: bestTextLLM)
        print()

        guard let vlm = bestVLM, let text = bestTextLLM else { return }

        if vlm.modelName == configuration.modelName,
           text.modelName == configuration.textModelName {
            print("Current configuration already uses the best models.")
            return
        }

        try promptConfigUpdate(
            bestVLMName: vlm.modelName, bestTextLLMName: text.modelName, configuration: configuration
        )
    }

    private func bestQualifyingResult<T: BenchmarkResultProtocol>(from results: [T]) -> T? {
        results.filter { !$0.isDisqualified }
            .sorted { lhs, rhs in
                if lhs.score != rhs.score { return lhs.score > rhs.score }
                return lhs.elapsedSeconds < rhs.elapsedSeconds
            }.first
    }

    private func printBestModel(label: String, result: (some BenchmarkResultProtocol)?) {
        if let result {
            print("Best \(label): \(result.modelName) (\(TerminalUtils.formatPercent(result.score)))")
        } else {
            print("Best \(label): No qualifying results")
        }
    }

    private func promptConfigUpdate(
        bestVLMName: String, bestTextLLMName: String, configuration: Configuration
    ) throws {
        guard let choice = TerminalUtils.menu(
            "Would you like to update your configuration?",
            options: [
                "Update config to use best VLM + best TextLLM",
                "Keep current configuration",
            ]
        ), choice == 0 else {
            print("Keeping current configuration.")
            return
        }

        var newConfig = configuration
        newConfig.modelName = bestVLMName
        newConfig.textModelName = bestTextLLMName

        let path = config ?? Configuration.defaultConfigPath
        try newConfig.save(to: path)
        print("Configuration saved to \(path)")
    }
}
