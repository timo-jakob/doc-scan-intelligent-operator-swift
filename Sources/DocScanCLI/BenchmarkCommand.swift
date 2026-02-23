import ArgumentParser
import DocScanCore
import Foundation
import MLX

struct BenchmarkCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "benchmark",
        abstract: "Evaluate model pairs against a labeled document corpus"
    )

    @Argument(help: "Directory containing positive sample PDFs (documents that match the type)")
    var positiveDir: String

    @Option(name: .shortAndLong, help: "Document type to benchmark: 'invoice' (default) or 'prescription'")
    var type: String = "invoice"

    @Option(name: .long, help: "Directory containing negative sample PDFs (documents that do NOT match the type)")
    var negativeDir: String?

    @Option(name: .shortAndLong, help: "Path to configuration file")
    var config: String?

    @Flag(name: .shortAndLong, help: "Enable verbose output")
    var verbose: Bool = false

    func run() async throws {
        // Cap MLX memory at 80% of physical RAM to leave headroom for the OS.
        // Prevents jetsam kills after a previous crash left GPU resources unreleased.
        let memoryBudget = Int(Double(ProcessInfo.processInfo.physicalMemory) * 0.8)
        Memory.memoryLimit = memoryBudget

        let documentType = try parseDocumentType()
        var configuration = try loadConfiguration()
        configuration.verbose = verbose

        printBenchmarkHeader(configuration, documentType: documentType)

        let resolvedPositiveDir = PathUtils.resolvePath(positiveDir)
        let resolvedNegativeDir = negativeDir.map { PathUtils.resolvePath($0) }

        let engine = BenchmarkEngine(
            configuration: configuration,
            documentType: documentType,
            verbose: verbose
        )

        // Phase A: Initial benchmark run
        let initialResults = try await runPhaseA(
            engine: engine,
            positiveDir: resolvedPositiveDir,
            negativeDir: resolvedNegativeDir
        )

        // Phase A.1: Verification pause
        try runPhaseA1(positiveDir: resolvedPositiveDir, negativeDir: resolvedNegativeDir)

        // Phase A.2: Credential check
        let apiToken = try runPhaseA2(configuration: &configuration)

        // Phase B: Model discovery
        guard let pairs = try await runPhaseB(
            configuration: configuration,
            apiToken: apiToken
        ) else {
            print("Model discovery skipped. Benchmark complete.")
            return
        }

        // Phase B.1: Timeout selection
        let timeout = runPhaseB1()

        // Load verified ground truths
        var allPDFs = try engine.enumeratePDFs(in: resolvedPositiveDir)
        if let negDir = resolvedNegativeDir {
            allPDFs += try engine.enumeratePDFs(in: negDir)
        }
        let groundTruths = try engine.loadGroundTruths(pdfPaths: allPDFs)

        // Phase C: Benchmark pairs
        let results = try await runPhaseC(
            engine: engine,
            pairs: pairs,
            pdfPaths: allPDFs,
            groundTruths: groundTruths,
            timeoutSeconds: timeout
        )

        // Merge Phase A results with Phase C, avoiding duplicates
        let phaseCPairs = Set(results.map { "\($0.vlmModelName)\n\($0.textModelName)" })
        let uniqueInitial = initialResults.filter {
            !phaseCPairs.contains("\($0.vlmModelName)\n\($0.textModelName)")
        }
        let allResults = results + uniqueInitial

        // Phase D + Cleanup
        try runPhaseDAndCleanup(
            engine: engine, allResults: allResults,
            configuration: configuration, pairs: pairs
        )
    }

    private func runPhaseDAndCleanup(
        engine: BenchmarkEngine, allResults: [ModelPairResult],
        configuration: Configuration, pairs: [ModelPair]
    ) throws {
        let finalPair = try runPhaseD(
            results: allResults,
            configuration: configuration,
            configPath: config
        )

        printBenchmarkPhaseHeader("E", title: "Model Cache Cleanup")
        engine.cleanupBenchmarkedModels(
            benchmarkedPairs: pairs,
            keepVLM: finalPair.vlm,
            keepText: finalPair.text
        )
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
        print("DocScan Benchmark")
        print("=================")
        print("Document type: \(documentType.displayName)")
        print("VLM Model: \(configuration.modelName)")
        print("Text Model: \(configuration.textModelName)")
        print()
    }

    func printBenchmarkPhaseHeader(_ phase: String, title: String) {
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("Phase \(phase): \(title)")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print()
    }
}
