import Foundation
import ArgumentParser
import DocScanCore

@main
struct DocScanCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "docscan",
        abstract: "AI-powered invoice detection and renaming using dual verification (VLM + OCR)",
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
            print("DocScan - Invoice Detection with Dual Verification")
            print("==================================================")
            print(configuration)
            print()
        }

        // Validate PDF exists
        guard FileManager.default.fileExists(atPath: pdfPath) else {
            throw DocScanError.fileNotFound(pdfPath)
        }

        // Analyze invoice with dual verification
        print("Analyzing: \(pdfPath)")
        print("Running dual verification (VLM + OCR in parallel)...")
        print()

        let detector = InvoiceDetector(config: configuration)
        let verification = try await detector.analyze(pdfPath: pdfPath)

        // Display results
        displayVerificationResults(verification)

        // Determine final result
        let finalData: InvoiceData
        if verification.hasConflict {
            // Ask user to resolve conflict
            finalData = try resolveConflict(verification)
        } else {
            // Both agree, use the result automatically
            if let agreedResult = verification.agreedResult {
                print("✅ VLM and OCR agree - proceeding automatically")
                print()
                finalData = InvoiceData(from: agreedResult, verificationResult: verification)
            } else {
                print("❌ Both methods failed to extract data")
                throw ExitCode.failure
            }
        }

        // Check if it's an invoice
        guard finalData.isInvoice else {
            print("❌ Document is not an invoice")
            throw ExitCode.failure
        }

        // Extract data
        guard let date = finalData.date, let company = finalData.company else {
            print("⚠️  Could not extract complete invoice data")
            if let date = finalData.date {
                print("   Date: \(formatDate(date))")
            }
            if let company = finalData.company {
                print("   Company: \(company)")
            }
            throw ExitCode.failure
        }

        print("Final extracted data:")
        print("   Date: \(formatDate(date))")
        print("   Company: \(company)")

        // Generate new filename
        guard let newFilename = detector.generateFilename(from: finalData) else {
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

    private func displayVerificationResults(_ verification: VerificationResult) {
        print("╔══════════════════════════════════════════════════╗")
        print("║         Dual Verification Results              ║")
        print("╠══════════════════════════════════════════════════╣")
        print("║ VLM Results:                                    ║")
        displayResult(verification.vmlResult, prefix: "║   ")
        print("║                                                 ║")
        print("║ OCR Results:                                    ║")
        displayResult(verification.ocrResult, prefix: "║   ")
        print("╚══════════════════════════════════════════════════╝")
        print()

        if verification.hasConflict {
            print("⚠️  CONFLICTS DETECTED:")
            for conflict in verification.conflicts {
                print("   - \(conflict)")
            }
            print()
        }
    }

    private func displayResult(_ result: ExtractionResult, prefix: String) {
        print("\(prefix)Is Invoice: \(result.isInvoice ? "✅ Yes" : "❌ No")      ")
        if let date = result.date {
            print("\(prefix)Date: \(formatDate(date))                  ")
        } else {
            print("\(prefix)Date: ❌ Not found                        ")
        }
        if let company = result.company {
            let truncated = String(company.prefix(30))
            print("\(prefix)Company: \(truncated)                     ")
        } else {
            print("\(prefix)Company: ❌ Not found                     ")
        }
    }

    private func resolveConflict(_ verification: VerificationResult) throws -> InvoiceData {
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("⚠️  CONFLICT RESOLUTION REQUIRED")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print()

        let vml = verification.vmlResult
        let ocr = verification.ocrResult

        // Resolve each conflict
        var finalIsInvoice = vml.isInvoice
        var finalDate = vml.date
        var finalCompany = vml.company

        // Invoice detection conflict
        if vml.isInvoice != ocr.isInvoice {
            print("Conflict: Invoice Detection")
            print("  [1] VLM says: \(vml.isInvoice ? "Invoice" : "Not an invoice")")
            print("  [2] OCR says: \(ocr.isInvoice ? "Invoice" : "Not an invoice")")
            let choice = promptChoice(validChoices: ["1", "2"])
            finalIsInvoice = choice == "1" ? vml.isInvoice : ocr.isInvoice
            print()
        }

        // Date conflict
        if vml.date != ocr.date {
            print("Conflict: Invoice Date")
            print("  [1] VLM says: \(vml.date.map { formatDate($0) } ?? "Not found")")
            print("  [2] OCR says: \(ocr.date.map { formatDate($0) } ?? "Not found")")
            let choice = promptChoice(validChoices: ["1", "2"])
            finalDate = choice == "1" ? vml.date : ocr.date
            print()
        }

        // Company conflict
        if vml.company != ocr.company {
            print("Conflict: Company Name")
            print("  [1] VLM says: \(vml.company ?? "Not found")")
            print("  [2] OCR says: \(ocr.company ?? "Not found")")
            let choice = promptChoice(validChoices: ["1", "2"])
            finalCompany = choice == "1" ? vml.company : ocr.company
            print()
        }

        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print()

        return InvoiceData(
            isInvoice: finalIsInvoice,
            date: finalDate,
            company: finalCompany,
            verificationResult: verification
        )
    }

    private func promptChoice(validChoices: [String]) -> String {
        while true {
            print("Enter your choice: ", terminator: "")
            if let input = readLine()?.trimmingCharacters(in: .whitespaces),
               validChoices.contains(input) {
                return input
            }
            print("Invalid choice. Please enter one of: \(validChoices.joined(separator: ", "))")
        }
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}
