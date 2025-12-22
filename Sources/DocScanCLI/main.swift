import Foundation
import ArgumentParser
import DocScanCore

@main
struct DocScanCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "docscan",
        abstract: "AI-powered invoice detection and renaming using Vision-Language Models",
        version: "1.0.0"
    )

    @Argument(help: "Path to the PDF file to analyze")
    var pdfPath: String

    @Option(name: .shortAndLong, help: "Path to configuration file")
    var config: String?

    @Option(name: .shortAndLong, help: "Model to use (e.g., 'mlx-community/Qwen2-VL-2B-Instruct-4bit')")
    var model: String?

    @Flag(name: .shortAndLong, help: "Preview changes without renaming")
    var dryRun: Bool = false

    @Flag(name: .shortAndLong, help: "Enable verbose output")
    var verbose: Bool = false

    @Option(name: .long, help: "Directory to cache models")
    var cacheDir: String?

    @Option(name: .long, help: "Maximum tokens to generate")
    var maxTokens: Int?

    @Option(name: .long, help: "Temperature for generation (0.0-1.0)")
    var temperature: Double?

    func run() async throws {
        // Load configuration
        var configuration: Configuration
        if let configPath = config {
            configuration = try Configuration.load(from: configPath)
        } else {
            configuration = Configuration.default
        }

        // Override with CLI arguments
        if let model = model {
            configuration.modelName = model
        }
        if let cacheDir = cacheDir {
            configuration.modelCacheDir = cacheDir
        }
        if let maxTokens = maxTokens {
            configuration.maxTokens = maxTokens
        }
        if let temperature = temperature {
            configuration.temperature = temperature
        }
        configuration.verbose = verbose

        if verbose {
            print("DocScan - Invoice Detection and Renaming")
            print("========================================")
            print(configuration)
            print()
        }

        // Validate PDF exists
        guard FileManager.default.fileExists(atPath: pdfPath) else {
            throw DocScanError.fileNotFound(pdfPath)
        }

        // Analyze invoice
        print("Analyzing: \(pdfPath)")
        let detector = InvoiceDetector(config: configuration)
        let invoiceData = try await detector.analyze(pdfPath: pdfPath)

        // Check if it's an invoice
        guard invoiceData.isInvoice else {
            print("❌ Document is not an invoice")
            throw ExitCode.failure
        }

        print("✅ Document is an invoice")

        // Extract data
        guard let date = invoiceData.date, let company = invoiceData.company else {
            print("⚠️  Could not extract complete invoice data")
            if let date = invoiceData.date {
                print("   Date: \(formatDate(date))")
            }
            if let company = invoiceData.company {
                print("   Company: \(company)")
            }
            throw ExitCode.failure
        }

        print("   Date: \(formatDate(date))")
        print("   Company: \(company)")

        // Generate new filename
        guard let newFilename = detector.generateFilename(from: invoiceData) else {
            print("⚠️  Could not generate filename")
            throw ExitCode.failure
        }

        print()
        print("New filename: \(newFilename)")

        // Rename file
        let renamer = FileRenamer(verbose: verbose)
        let newPath = try renamer.rename(
            from: pdfPath,
            to: newFilename,
            dryRun: dryRun
        )

        if dryRun {
            print()
            print("✨ Dry run completed - no files were modified")
        } else {
            print()
            print("✨ Successfully renamed to: \(newPath)")
        }
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}
