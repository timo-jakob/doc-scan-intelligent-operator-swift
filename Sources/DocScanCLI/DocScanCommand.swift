import Foundation
import ArgumentParser
import DocScanCore

@main
struct DocScanCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "docscan",
        abstract: "AI-powered document detection and renaming using two-phase verification",
        discussion: """
        Phase 1: Categorization (VLM + OCR in parallel) - Does this match the document type?
        Phase 2: Data Extraction (OCR + TextLLM only) - Extract date and secondary field

        Supported document types:
          invoice      - Invoices, bills, receipts (extracts: date, company)
          prescription - Doctor's prescriptions (extracts: date, doctor)
        """,
        version: "2.0.0"
    )

    @Argument(help: "Path to the PDF file to analyze")
    var pdfPath: String

    @Option(name: .shortAndLong, help: "Path to configuration file")
    var config: String?

    @Option(name: .shortAndLong, help: "Document type to detect: 'invoice' (default) or 'prescription'")
    var type: String = "invoice"

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
        // Parse document type
        let documentType: DocumentType
        switch type.lowercased() {
        case "invoice":
            documentType = .invoice
        case "prescription":
            documentType = .prescription
        default:
            print("❌ Invalid document type: '\(type)'")
            print("   Valid types: invoice, prescription")
            throw ExitCode.failure
        }

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
            print("DocScan - Two-Phase Document Detection")
            print("======================================")
            print("Document type: \(documentType.displayName)")
            print(configuration)
            print()
        }

        // Validate PDF path is not empty
        guard !pdfPath.isEmpty else {
            throw DocScanError.invalidInput("PDF path cannot be empty. Use '.' to refer to the current directory.")
        }

        // Convert relative path to absolute path with symlink resolution and normalization
        let finalPdfPath = PathUtils.resolvePath(pdfPath)

        // Validate PDF exists
        guard FileManager.default.fileExists(atPath: finalPdfPath) else {
            throw DocScanError.fileNotFound(finalPdfPath)
        }

        print("Analyzing: \(finalPdfPath)")
        print("Document type: \(documentType.displayName)")
        print()

        let detector = DocumentDetector(config: configuration, documentType: documentType)

        // ============================================================
        // PHASE 1: Categorization (VLM + OCR in parallel)
        // ============================================================
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("📋 PHASE 1: Categorization (VLM + OCR in parallel)")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print()

        let categorization = try await detector.categorize(pdfPath: finalPdfPath)

        // Display categorization results
        displayCategorizationResults(categorization, documentType: documentType)

        // Determine if we should proceed
        let isMatch: Bool
        let typeName = documentType.displayName.lowercased()

        // Check for timeouts
        let vlmTimedOut = categorization.vlmResult.method.contains("timeout")
        let ocrTimedOut = categorization.ocrResult.method.contains("timeout")

        if vlmTimedOut && ocrTimedOut {
            print("❌ Both methods timed out")
            throw ExitCode.failure
        } else if vlmTimedOut {
            print("⏱️  VLM timed out - using OCR result")
            isMatch = categorization.ocrResult.isMatch
        } else if ocrTimedOut {
            print("⏱️  OCR timed out - using VLM result")
            isMatch = categorization.vlmResult.isMatch
        } else if categorization.bothAgree {
            // Both agree
            isMatch = categorization.agreedIsMatch ?? false
            let vlmLabel = categorization.vlmResult.shortDisplayLabel
            let textLabel = categorization.ocrResult.shortDisplayLabel
            if isMatch {
                print("✅ \(vlmLabel) and \(textLabel) agree: This IS a \(typeName)")
            } else {
                print("✅ \(vlmLabel) and \(textLabel) agree: This is NOT a \(typeName)")
            }
        } else {
            // Conflict - need resolution
            isMatch = try resolveCategorization(categorization, autoResolve: autoResolve, documentType: documentType)
        }

        print()

        // Exit if document doesn't match type
        guard isMatch else {
            print("❌ Document is not a \(typeName) - exiting")
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

        // Determine field name based on document type
        let secondaryFieldName = documentType == .invoice ? "Company" : "Doctor"
        let secondaryFieldEmoji = documentType == .invoice ? "🏢" : "👨‍⚕️"

        // Check extraction results
        // For invoices: require both date and company
        // For prescriptions: require date, doctor and patient are optional
        guard let date = extraction.date else {
            print("⚠️  Could not extract date from \(typeName)")
            print("   Date: ❌ Not found")
            if let field = extraction.secondaryField {
                print("   \(secondaryFieldName): \(field)")
            }
            if documentType == .prescription, let patient = extraction.patientName {
                print("   Patient: \(patient)")
            }
            throw ExitCode.failure
        }

        // For invoices, company is required
        if documentType == .invoice && extraction.secondaryField == nil {
            print("⚠️  Could not extract company from invoice")
            print("   Date: \(formatDate(date))")
            print("   Company: ❌ Not found")
            throw ExitCode.failure
        }

        print("Extracted data:")
        print("   📅 Date: \(formatDate(date))")
        if let field = extraction.secondaryField {
            print("   \(secondaryFieldEmoji) \(secondaryFieldName): \(field)")
        } else if documentType == .prescription {
            print("   \(secondaryFieldEmoji) \(secondaryFieldName): Not found (will be excluded from filename)")
        }
        if documentType == .prescription {
            if let patient = extraction.patientName {
                print("   👤 Patient: \(patient)")
            } else {
                print("   👤 Patient: Not found (will be excluded from filename)")
            }
        }
        print()

        // Create final document data
        let finalData = DocumentData(
            documentType: documentType,
            isMatch: true,
            date: date,
            secondaryField: extraction.secondaryField,
            patientName: extraction.patientName,
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
            from: finalPdfPath,
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

    private func displayCategorizationResults(_ categorization: CategorizationVerification, documentType: DocumentType) {
        print("╔══════════════════════════════════════════════════╗")
        print("║         Categorization Results                   ║")
        print("╠══════════════════════════════════════════════════╣")
        print("║ \(categorization.vlmResult.displayLabel):".padding(toLength: 51, withPad: " ", startingAt: 0) + "║")
        displayCategorizationResult(categorization.vlmResult, prefix: "║   ", documentType: documentType)
        print("║                                                  ║")
        print("║ \(categorization.ocrResult.displayLabel):".padding(toLength: 51, withPad: " ", startingAt: 0) + "║")
        displayCategorizationResult(categorization.ocrResult, prefix: "║   ", documentType: documentType)
        print("╚══════════════════════════════════════════════════╝")
        print()
    }

    private func displayCategorizationResult(_ result: CategorizationResult, prefix: String, documentType: DocumentType) {
        let typeName = documentType.displayName
        let matchStatus = result.isMatch ? "✅ \(typeName)" : "❌ Not \(typeName)"
        print("\(prefix)\(matchStatus) (confidence: \(result.confidence))")
        if let reason = result.reason, verbose {
            let truncated = String(reason.prefix(40))
            print("\(prefix)Reason: \(truncated)")
        }
    }

    // MARK: - Conflict Resolution

    private func resolveCategorization(
        _ categorization: CategorizationVerification,
        autoResolve: String?,
        documentType: DocumentType
    ) throws -> Bool {
        let vlmLabel = categorization.vlmResult.shortDisplayLabel
        let textLabel = categorization.ocrResult.shortDisplayLabel
        let typeName = documentType.displayName

        print("⚠️  CATEGORIZATION CONFLICT")
        print()
        print("  \(vlmLabel) says: \(categorization.vlmResult.isMatch ? typeName : "Not a \(typeName.lowercased())")")
        print("  \(textLabel) says: \(categorization.ocrResult.isMatch ? typeName : "Not a \(typeName.lowercased())")")
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
            let result = useVLM ? categorization.vlmResult.isMatch : categorization.ocrResult.isMatch
            let chosenLabel = useVLM ? vlmLabel : textLabel
            print("🤖 Auto-resolve: Using \(chosenLabel) → \(result ? typeName : "Not a \(typeName.lowercased())")")
            return result
        }

        // Interactive resolution
        print("Which result do you trust?")
        print("  [1] \(vlmLabel): \(categorization.vlmResult.isMatch ? typeName : "Not a \(typeName.lowercased())")")
        print("  [2] \(textLabel): \(categorization.ocrResult.isMatch ? typeName : "Not a \(typeName.lowercased())")")

        while true {
            print("Enter your choice (1 or 2): ", terminator: "")
            if let input = readLine()?.trimmingCharacters(in: .whitespaces) {
                if input == "1" {
                    return categorization.vlmResult.isMatch
                } else if input == "2" {
                    return categorization.ocrResult.isMatch
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
