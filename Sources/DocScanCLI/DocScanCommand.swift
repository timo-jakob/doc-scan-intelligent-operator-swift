import ArgumentParser
import Darwin
import DocScanCore
import Foundation

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

    @Option(name: .shortAndLong, help: "VLM model for categorization")
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

    @Option(name: .long, help: "Auto-resolve categorization conflicts: 'vlm' or 'ocr'")
    var autoResolve: String?

    func run() async throws {
        let documentType = try parseDocumentType()
        var configuration = try loadConfiguration()
        applyCliOverrides(to: &configuration)

        if verbose { printVerboseHeader(configuration, documentType: documentType) }

        let finalPdfPath = try validateAndResolvePath()

        // Create model managers, print startup info, and preload
        let vlmManager = ModelManager(config: configuration)
        let textManager = TextLLMManager(config: configuration)
        try await printStartupAndPreload(
            vlmManager: vlmManager,
            textManager: textManager,
            vlmModelName: configuration.modelName,
            textModelName: textManager.modelName
        )

        // Create detector reusing the preloaded managers
        let detector = DocumentDetector(
            config: configuration,
            documentType: documentType,
            vlmProvider: vlmManager,
            textLLM: textManager
        )

        // PHASE 1: Categorization
        if verbose {
            print("Analyzing: \(finalPdfPath)")
            print("Document type: \(documentType.displayName)")
            print()
            printPhaseHeader(number: 1, title: "Categorization (VLM + OCR in parallel)")
        }

        let categorization = try await detector.categorize(pdfPath: finalPdfPath)

        let isMatch: Bool
        if verbose {
            displayCategorizationResults(categorization, documentType: documentType)
            isMatch = try determineIsMatchVerbose(categorization, documentType: documentType)
            print()
        } else {
            isMatch = try determineIsMatchCompact(categorization, documentType: documentType)
        }

        guard isMatch else {
            if verbose { print("❌ Document is not a \(documentType.displayName.lowercased()) - exiting") }
            throw ExitCode.failure
        }

        // PHASE 2: Data Extraction
        if verbose {
            printPhaseHeader(number: 2, title: "Data Extraction (OCR + TextLLM)")
        }

        let extraction = try await detector.extractData()
        let date = try validateExtraction(extraction, documentType: documentType)

        if verbose {
            displayExtractionResults(extraction, date: date, documentType: documentType)
        } else {
            printCompactPhase2(extraction, date: date, documentType: documentType)
        }

        let finalData = DocumentData(
            documentType: documentType,
            isMatch: true,
            date: date,
            secondaryField: extraction.secondaryField,
            patientName: extraction.patientName,
            categorization: categorization
        )

        guard let newFilename = detector.generateFilename(from: finalData) else {
            print("⚠️  Could not generate filename")
            throw ExitCode.failure
        }

        let originalFilename = URL(fileURLWithPath: finalPdfPath).lastPathComponent
        let renamer = FileRenamer(verbose: verbose)
        let newPath = try renamer.rename(from: finalPdfPath, to: newFilename, dryRun: dryRun)

        if verbose {
            print("New filename: \(newFilename)")
            print()
            print(dryRun
                ? "✨ Dry run completed - no files were modified"
                : "✨ Successfully renamed to: \(newPath)")
        } else {
            let action = dryRun ? "Dry run" : "Renamed"
            writeStdout("✏️   \(action)  \(originalFilename) → \(newFilename)\n")
        }
    }
}

// MARK: - Setup Helpers

extension DocScanCommand {
    private func parseDocumentType() throws -> DocumentType {
        switch type.lowercased() {
        case "invoice": return .invoice
        case "prescription": return .prescription
        default:
            print("❌ Invalid document type: '\(type)'")
            print("   Valid types: invoice, prescription")
            throw ExitCode.failure
        }
    }

    private func loadConfiguration() throws -> Configuration {
        if let configPath = config {
            return try Configuration.load(from: configPath)
        }
        return Configuration.defaultConfiguration
    }

    private func applyCliOverrides(to configuration: inout Configuration) {
        if let model { configuration.modelName = model }
        if let cacheDir { configuration.modelCacheDir = cacheDir }
        if let maxTokens { configuration.maxTokens = maxTokens }
        if let temperature { configuration.temperature = temperature }
        if let pdfDpi { configuration.pdfDPI = pdfDpi }
        configuration.verbose = verbose
    }

    private func printVerboseHeader(_ configuration: Configuration, documentType: DocumentType) {
        print("DocScan - Two-Phase Document Detection")
        print("======================================")
        print("Document type: \(documentType.displayName)")
        print(configuration)
        print()
    }

    private func validateAndResolvePath() throws -> String {
        guard !pdfPath.isEmpty else {
            throw DocScanError.invalidInput(
                "PDF path cannot be empty. Use '.' to refer to the current directory."
            )
        }
        let resolved = PathUtils.resolvePath(pdfPath)
        guard FileManager.default.fileExists(atPath: resolved) else {
            throw DocScanError.fileNotFound(resolved)
        }
        return resolved
    }
}

// MARK: - Startup

extension DocScanCommand {
    /// Print model info lines and preload both models, showing a progress bar when downloading.
    /// On a non-TTY stdout (piped/redirected), skips in-place \r rewrites to avoid garbled output.
    private func printStartupAndPreload(
        vlmManager: ModelManager,
        textManager: TextLLMManager,
        vlmModelName: String,
        textModelName: String
    ) async throws {
        let tty = isInteractiveTerminal

        try await preloadModel(
            emoji: "🤖", label: "VLM    ", modelName: vlmModelName, tty: tty
        ) { handler in
            try await vlmManager.preload(modelName: vlmModelName, progressHandler: handler)
        }

        try await preloadModel(
            emoji: "📝", label: "Text   ", modelName: textModelName, tty: tty
        ) { handler in
            try await textManager.preload(progressHandler: handler)
        }
    }

    /// Preload a single model, showing a progress bar only when a download is actually happening.
    /// `label` should be padded to 7 characters (e.g. "VLM    ", "Text   ") for column alignment.
    private func preloadModel(
        emoji: String,
        label: String,
        modelName: String,
        tty: Bool,
        load: (@escaping (Double) -> Void) async throws -> Void
    ) async throws {
        if tty { writeStdout("\(emoji) \(label)\(modelName)") }
        var downloading = false
        try await load { fraction in
            if fraction < 0.999 { downloading = true }
            guard downloading, tty else { return }
            let bar = Self.progressBar(fraction: fraction)
            let pct = String(format: "%3d", Int(fraction * 100))
            self.writeStdout("\r\(emoji) \(label)\(modelName)  ⬇️  \(bar) \(pct)%")
        }
        if tty {
            writeStdout(downloading ? "\r\(emoji) \(label)\(modelName)  ✅ ready\n" : "\n")
        } else {
            let suffix = downloading ? "  ✅ ready" : ""
            writeStdout("\(emoji) \(label)\(modelName)\(suffix)\n")
        }
    }

    /// True when stdout is connected to an interactive terminal (not piped or redirected).
    private var isInteractiveTerminal: Bool {
        isatty(STDOUT_FILENO) != 0
    }

    /// Write directly to stdout without buffering (needed for in-place \r updates).
    private func writeStdout(_ string: String) {
        FileHandle.standardOutput.write(Data(string.utf8))
    }

    /// Build a fixed-width ASCII progress bar for download display.
    private static func progressBar(fraction: Double, width: Int = 16) -> String {
        let filled = min(width, Int(fraction * Double(width)))
        let empty = width - filled
        return "[" + String(repeating: "█", count: filled) + String(repeating: "░", count: empty) + "]"
    }
}

// MARK: - Phase 1: Verbose Output

extension DocScanCommand {
    private func printPhaseHeader(number: Int, title: String) {
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("Phase \(number): \(title)")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print()
    }

    private func displayCategorizationResults(
        _ categorization: CategorizationVerification,
        documentType: DocumentType
    ) {
        print("╔══════════════════════════════════════════════════╗")
        print("║         Categorization Results                   ║")
        print("╠══════════════════════════════════════════════════╣")
        let vlmLine = "║ \(categorization.vlmResult.displayLabel):"
        print(vlmLine.padding(toLength: 51, withPad: " ", startingAt: 0) + "║")
        displayCategorizationResult(categorization.vlmResult, prefix: "║   ", documentType: documentType)
        print("║                                                  ║")
        let ocrLine = "║ \(categorization.ocrResult.displayLabel):"
        print(ocrLine.padding(toLength: 51, withPad: " ", startingAt: 0) + "║")
        displayCategorizationResult(categorization.ocrResult, prefix: "║   ", documentType: documentType)
        print("╚══════════════════════════════════════════════════╝")
        print()
    }

    private func displayCategorizationResult(
        _ result: CategorizationResult,
        prefix: String,
        documentType: DocumentType
    ) {
        let typeName = documentType.displayName
        let matchStatus = result.isMatch ? "✅ \(typeName)" : "❌ Not \(typeName)"
        print("\(prefix)\(matchStatus) (confidence: \(result.confidence))")
        if let reason = result.reason, verbose {
            print("\(prefix)Reason: \(String(reason.prefix(40)))")
        }
    }

    private func determineIsMatchVerbose(
        _ categorization: CategorizationVerification,
        documentType: DocumentType
    ) throws -> Bool {
        let vlmTimedOut = categorization.vlmResult.isTimedOut
        let ocrTimedOut = categorization.ocrResult.isTimedOut
        let typeName = documentType.displayName.lowercased()

        if vlmTimedOut, ocrTimedOut {
            print("❌ Both methods timed out")
            throw ExitCode.failure
        }
        if vlmTimedOut {
            print("⏱️  VLM timed out - using OCR result")
            return categorization.ocrResult.isMatch
        }
        if ocrTimedOut {
            print("⏱️  OCR timed out - using VLM result")
            return categorization.vlmResult.isMatch
        }
        if categorization.bothAgree {
            let isMatch = categorization.agreedIsMatch ?? false
            let vlmLabel = categorization.vlmResult.shortDisplayLabel
            let textLabel = categorization.ocrResult.shortDisplayLabel
            print("✅ \(vlmLabel) and \(textLabel) agree: This \(isMatch ? "IS" : "is NOT") a \(typeName)")
            return isMatch
        }
        return try resolveCategorizationVerbose(categorization, documentType: documentType)
    }

    private func resolveCategorizationVerbose(
        _ categorization: CategorizationVerification,
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

        if let autoResolveMode = autoResolve {
            return try applyAutoResolveVerbose(autoResolveMode, categorization: categorization, documentType: documentType)
        }
        return try interactiveResolveVerbose(categorization, documentType: documentType)
    }

    private func applyAutoResolveVerbose(
        _ mode: String,
        categorization: CategorizationVerification,
        documentType: DocumentType
    ) throws -> Bool {
        guard ["vlm", "ocr"].contains(mode.lowercased()) else {
            print("❌ Invalid --auto-resolve option: '\(mode)'")
            print("   Valid options: vlm, ocr")
            throw ExitCode.failure
        }
        let useVLM = mode.lowercased() == "vlm"
        let result = useVLM ? categorization.vlmResult.isMatch : categorization.ocrResult.isMatch
        let chosenLabel = useVLM ? categorization.vlmResult.shortDisplayLabel : categorization.ocrResult.shortDisplayLabel
        let typeName = documentType.displayName.lowercased()
        print("🤖 Auto-resolve: Using \(chosenLabel) → \(result ? typeName : "Not a \(typeName)")")
        return result
    }

    private func interactiveResolveVerbose(
        _ categorization: CategorizationVerification,
        documentType: DocumentType
    ) throws -> Bool {
        let vlmLabel = categorization.vlmResult.shortDisplayLabel
        let textLabel = categorization.ocrResult.shortDisplayLabel
        let typeName = documentType.displayName

        print("Which result do you trust?")
        print("  [1] \(vlmLabel): \(categorization.vlmResult.isMatch ? typeName : "Not a \(typeName.lowercased())")")
        print("  [2] \(textLabel): \(categorization.ocrResult.isMatch ? typeName : "Not a \(typeName.lowercased())")")

        while true {
            print("Enter your choice (1 or 2): ", terminator: "")
            guard let input = readLine()?.trimmingCharacters(in: .whitespaces) else {
                throw ExitCode.failure // stdin closed
            }
            if input == "1" { return categorization.vlmResult.isMatch }
            if input == "2" { return categorization.ocrResult.isMatch }
            print("Invalid choice. Please enter 1 or 2.")
        }
    }
}

// MARK: - Phase 1: Compact Output

extension DocScanCommand {
    private func determineIsMatchCompact(
        _ categorization: CategorizationVerification,
        documentType: DocumentType
    ) throws -> Bool {
        let vlmTimedOut = categorization.vlmResult.isTimedOut
        let ocrTimedOut = categorization.ocrResult.isTimedOut
        let vlmConf = categorization.vlmResult.confidence
        let ocrConf = categorization.ocrResult.confidence
        let typeName = documentType.displayName.lowercased()

        if vlmTimedOut, ocrTimedOut {
            writeStdout("📋 Phase 1  ❌ both methods timed out\n")
            throw ExitCode.failure
        }

        if vlmTimedOut {
            let isMatch = categorization.ocrResult.isMatch
            let label = isMatch ? "✅ \(typeName)" : "❌ unknown document"
            writeStdout("📋 Phase 1  \(label)  ⏱️ VLM · OCR: \(ocrConf)\n")
            return isMatch
        }

        if ocrTimedOut {
            let isMatch = categorization.vlmResult.isMatch
            let label = isMatch ? "✅ \(typeName)" : "❌ unknown document"
            writeStdout("📋 Phase 1  \(label)  VLM: \(vlmConf) · ⏱️ OCR\n")
            return isMatch
        }

        if categorization.bothAgree {
            let isMatch = categorization.agreedIsMatch ?? false
            let label = isMatch ? "✅ \(typeName)" : "❌ unknown document"
            writeStdout("📋 Phase 1  \(label)  VLM: \(vlmConf) · OCR: \(ocrConf)\n")
            return isMatch
        }

        return try resolveConflictCompact(
            categorization, documentType: documentType, vlmConf: vlmConf, ocrConf: ocrConf
        )
    }

    private func resolveConflictCompact(
        _ categorization: CategorizationVerification,
        documentType: DocumentType,
        vlmConf: String,
        ocrConf: String
    ) throws -> Bool {
        let vlmYN = categorization.vlmResult.isMatch ? "YES" : "NO"
        let ocrYN = categorization.ocrResult.isMatch ? "YES" : "NO"
        let conflictInfo = "VLM=\(vlmYN)(\(vlmConf)) · OCR=\(ocrYN)(\(ocrConf))"
        let prompt = "📋 Phase 1  ⚠️  conflict  \(conflictInfo)  →  [v]lm or [o]cr? "

        if let mode = autoResolve {
            guard ["vlm", "ocr"].contains(mode.lowercased()) else {
                print("❌ Invalid --auto-resolve option: '\(mode)'")
                throw ExitCode.failure
            }
            let useVLM = mode.lowercased() == "vlm"
            let result = useVLM ? categorization.vlmResult.isMatch : categorization.ocrResult.isMatch
            let typeName = documentType.displayName.lowercased()
            let matchStr = result ? "✅ \(typeName)" : "❌ unknown document"
            writeStdout("📋 Phase 1  ⚠️  \(matchStr)  \(conflictInfo)  [auto:\(mode.lowercased())]\n")
            return result
        }

        writeStdout(prompt)
        while true {
            guard let input = readLine()?.trimmingCharacters(in: .whitespaces).lowercased() else {
                writeStdout("\n")
                throw ExitCode.failure // stdin closed
            }
            if input == "v" || input == "vlm" { return categorization.vlmResult.isMatch }
            if input == "o" || input == "ocr" { return categorization.ocrResult.isMatch }
            // Invalid input — re-prompt on the same line when in a TTY, new line otherwise
            let prefix = isInteractiveTerminal ? "\r" : ""
            writeStdout("\(prefix)\(prompt)")
        }
    }
}

// MARK: - Phase 2

extension DocScanCommand {
    private func validateExtraction(
        _ extraction: ExtractionResult,
        documentType: DocumentType
    ) throws -> Date {
        let typeName = documentType.displayName.lowercased()
        guard let date = extraction.date else {
            print("⚠️  Could not extract date from \(typeName)")
            print("   Date: ❌ Not found")
            throw ExitCode.failure
        }
        if documentType == .invoice, extraction.secondaryField == nil {
            print("⚠️  Could not extract company from invoice")
            print("   Date: \(formatDate(date))")
            print("   Company: ❌ Not found")
            throw ExitCode.failure
        }
        return date
    }

    private func displayExtractionResults(
        _ extraction: ExtractionResult,
        date: Date,
        documentType: DocumentType
    ) {
        let fieldName = documentType == .invoice ? "Company" : "Doctor"
        let fieldEmoji = documentType == .invoice ? "🏢" : "👨‍⚕️"
        print("Extracted data:")
        print("   📅 Date: \(formatDate(date))")
        if let field = extraction.secondaryField {
            print("   \(fieldEmoji) \(fieldName): \(field)")
        } else if documentType == .prescription {
            print("   \(fieldEmoji) \(fieldName): Not found (will be excluded from filename)")
        }
        if documentType == .prescription {
            if let patient = extraction.patientName {
                print("   👤 Patient: \(patient)")
            } else {
                print("   👤 Patient: Not found (will be excluded from filename)")
            }
        }
        print()
    }

    private func printCompactPhase2(
        _ extraction: ExtractionResult,
        date: Date,
        documentType _: DocumentType
    ) {
        let dateStr = formatDate(date)
        if let field = extraction.secondaryField {
            writeStdout("📄 Phase 2  ✅ extracted  \(dateStr) · \(field)\n")
        } else {
            writeStdout("📄 Phase 2  ✅ extracted  \(dateStr)\n")
        }
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}
