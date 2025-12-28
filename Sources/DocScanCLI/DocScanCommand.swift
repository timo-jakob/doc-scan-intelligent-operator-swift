import Foundation
import ArgumentParser
import DocScanCore

@main
struct DocScanCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "docscan",
        abstract: "AI-powered invoice detection and renaming using two-phase verification",
        discussion: """
        Phase 1: Categorization (VLM + OCR in parallel) - Is this an invoice?
        Phase 2: Data Extraction (OCR + TextLLM only) - Extract date and company
        """,
        version: "2.0.0"
    )

    @Argument(help: "Path to the PDF file to analyze")
    var pdfPath: String

    @Option(name: .shortAndLong, help: "Path to configuration file")
    var config: String?

    @Option(name: .shortAndLong, help: "VLM model for categorization (e.g., 'mlx-community/Qwen2-VL-2B-Instruct-4bit')")
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

    @Option(name: .long, help: "DPI for PDF to image conversion (default: 150)")
    var pdfDpi: Int?

    @Option(name: .long, help: "Auto-resolve categorization conflicts: 'vlm' or 'ocr' (for testing/automation)")
    var autoResolve: String?

    func run() async throws {
        // Load configuration
        var configuration: Configuration
        if let configPath = config {
            configuration = try Configuration.load(from: configPath)
        } else {
            configuration = Configuration.defaultConfiguration
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
        if let pdfDpi = pdfDpi {
            configuration.pdfDPI = pdfDpi
        }
        configuration.verbose = verbose

        if verbose {
            print("DocScan - Two-Phase Invoice Detection")
            print("======================================")
            print(configuration)
            print()
        }

        // Validate PDF exists
        guard FileManager.default.fileExists(atPath: pdfPath) else {
            throw DocScanError.fileNotFound(pdfPath)
        }

        print("Analyzing: \(pdfPath)")
        print()

        let detector = InvoiceDetector(config: configuration)

        // ============================================================
        // PHASE 1: Categorization (VLM + OCR in parallel)
        // ============================================================
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("📋 PHASE 1: Categorization (VLM + OCR in parallel)")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print()

        let categorization = try await detector.categorize(pdfPath: pdfPath)

        // Display categorization results
        displayCategorizationResults(categorization)

        // Determine if we should proceed
        let isInvoice: Bool

        // Check for timeouts
        let vlmTimedOut = categorization.vlmResult.method.contains("timeout")
        let ocrTimedOut = categorization.ocrResult.method.contains("timeout")

        if vlmTimedOut && ocrTimedOut {
            print("❌ Both methods timed out")
            throw ExitCode.failure
        } else if vlmTimedOut {
            print("⏱️  VLM timed out - using OCR result")
            isInvoice = categorization.ocrResult.isInvoice
        } else if ocrTimedOut {
            print("⏱️  OCR timed out - using VLM result")
            isInvoice = categorization.vlmResult.isInvoice
        } else if categorization.bothAgree {
            // Both agree
            isInvoice = categorization.agreedIsInvoice ?? false
            if isInvoice {
                print("✅ VLM and OCR agree: This IS an invoice")
            } else {
                print("✅ VLM and OCR agree: This is NOT an invoice")
            }
        } else {
            // Conflict - need resolution
            isInvoice = try resolveCategorization(categorization, autoResolve: autoResolve)
        }

        print()

        // Exit if not an invoice
        guard isInvoice else {
            print("❌ Document is not an invoice - exiting")
            throw ExitCode.failure
        }

        // ============================================================
        // PHASE 2: Data Extraction (OCR + TextLLM only)
        // ============================================================
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("📄 PHASE 2: Data Extraction (OCR + TextLLM)")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print()

        let extraction = try await detector.extractData()

        // Check extraction results
        guard let date = extraction.date, let company = extraction.company else {
            print("⚠️  Could not extract complete invoice data")
            if let date = extraction.date {
                print("   Date: \(formatDate(date))")
            } else {
                print("   Date: ❌ Not found")
            }
            if let company = extraction.company {
                print("   Company: \(company)")
            } else {
                print("   Company: ❌ Not found")
            }
            throw ExitCode.failure
        }

        print("Extracted data:")
        print("   📅 Date: \(formatDate(date))")
        print("   🏢 Company: \(company)")
        print()

        // Create final invoice data
        let finalData = InvoiceData(
            isInvoice: true,
            date: date,
            company: company,
            categorization: categorization
        )

        // Generate new filename
        guard let newFilename = detector.generateFilename(from: finalData) else {
            print("⚠️  Could not generate filename")
            throw ExitCode.failure
        }

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

    // MARK: - Display Methods

    private func displayCategorizationResults(_ categorization: CategorizationVerification) {
        print("╔══════════════════════════════════════════════════╗")
        print("║         Categorization Results                 ║")
        print("╠══════════════════════════════════════════════════╣")
        print("║ VLM:                                            ║")
        displayCategorizationResult(categorization.vlmResult, prefix: "║   ")
        print("║                                                 ║")
        print("║ OCR:                                            ║")
        displayCategorizationResult(categorization.ocrResult, prefix: "║   ")
        print("╚══════════════════════════════════════════════════╝")
        print()
    }

    private func displayCategorizationResult(_ result: CategorizationResult, prefix: String) {
        let invoiceStatus = result.isInvoice ? "✅ Invoice" : "❌ Not Invoice"
        print("\(prefix)\(invoiceStatus) (confidence: \(result.confidence))")
        if let reason = result.reason, verbose {
            let truncated = String(reason.prefix(40))
            print("\(prefix)Reason: \(truncated)")
        }
    }

    // MARK: - Conflict Resolution

    private func resolveCategorization(_ categorization: CategorizationVerification, autoResolve: String?) throws -> Bool {
        print("⚠️  CATEGORIZATION CONFLICT")
        print()
        print("  VLM says: \(categorization.vlmResult.isInvoice ? "Invoice" : "Not an invoice")")
        print("  OCR says: \(categorization.ocrResult.isInvoice ? "Invoice" : "Not an invoice")")
        print()

        // Validate auto-resolve option
        if let autoResolveMode = autoResolve {
            let validModes = ["vlm", "ocr"]
            guard validModes.contains(autoResolveMode.lowercased()) else {
                print("❌ Invalid --auto-resolve option: '\(autoResolveMode)'")
                print("   Valid options: vlm, ocr")
                throw ExitCode.failure
            }

            let useVLM = autoResolveMode.lowercased() == "vlm"
            let result = useVLM ? categorization.vlmResult.isInvoice : categorization.ocrResult.isInvoice
            print("🤖 Auto-resolve: Using \(autoResolveMode.uppercased()) → \(result ? "Invoice" : "Not an invoice")")
            return result
        }

        // Interactive resolution
        print("Which result do you trust?")
        print("  [1] VLM: \(categorization.vlmResult.isInvoice ? "Invoice" : "Not an invoice")")
        print("  [2] OCR: \(categorization.ocrResult.isInvoice ? "Invoice" : "Not an invoice")")

        while true {
            print("Enter your choice (1 or 2): ", terminator: "")
            if let input = readLine()?.trimmingCharacters(in: .whitespaces) {
                if input == "1" {
                    return categorization.vlmResult.isInvoice
                } else if input == "2" {
                    return categorization.ocrResult.isInvoice
                }
            }
            print("Invalid choice. Please enter 1 or 2.")
        }
    }

    // MARK: - Helpers

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}
