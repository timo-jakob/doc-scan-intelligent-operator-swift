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
        let detector = try await createDetector(
            configuration: configuration, documentType: documentType
        )

        let (categorization, isMatch) = try await executePhase1(
            detector: detector, pdfPath: finalPdfPath, documentType: documentType
        )

        guard isMatch else {
            if verbose {
                let typeName = documentType.displayName.lowercased()
                print("❌ Document is not a \(typeName) - exiting")
            }
            throw ExitCode.failure
        }

        try await executePhase2(
            detector: detector,
            pdfPath: finalPdfPath,
            documentType: documentType,
            categorization: categorization
        )
    }

    private func createDetector(
        configuration: Configuration,
        documentType: DocumentType
    ) async throws -> DocumentDetector {
        let vlmManager = ModelManager(config: configuration)
        let textManager = TextLLMManager(config: configuration)
        try await printStartupAndPreload(
            vlmManager: vlmManager,
            textManager: textManager,
            vlmModelName: configuration.modelName,
            textModelName: textManager.modelName
        )
        return DocumentDetector(
            config: configuration,
            documentType: documentType,
            vlmProvider: vlmManager,
            textLLM: textManager
        )
    }

    private func executePhase1(
        detector: DocumentDetector,
        pdfPath: String,
        documentType: DocumentType
    ) async throws -> (CategorizationVerification, Bool) {
        if verbose {
            print("Analyzing: \(pdfPath)")
            print("Document type: \(documentType.displayName)")
            print()
            printPhaseHeader(
                number: 1,
                title: "Categorization (VLM + OCR in parallel)"
            )
        }

        let categorization = try await detector.categorize(pdfPath: pdfPath)

        let isMatch: Bool
        if verbose {
            displayCategorizationResults(categorization, documentType: documentType)
            isMatch = try determineIsMatchVerbose(categorization, documentType: documentType)
            print()
        } else {
            isMatch = try determineIsMatchCompact(categorization, documentType: documentType)
        }
        return (categorization, isMatch)
    }

    private func executePhase2(
        detector: DocumentDetector,
        pdfPath: String,
        documentType: DocumentType,
        categorization: CategorizationVerification
    ) async throws {
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

        let originalFilename = URL(fileURLWithPath: pdfPath).lastPathComponent
        let renamer = FileRenamer(verbose: verbose)
        let newPath = try renamer.rename(
            from: pdfPath, to: newFilename, dryRun: dryRun
        )

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
    var isInteractiveTerminal: Bool {
        isatty(STDOUT_FILENO) != 0
    }

    /// Write directly to stdout without buffering (needed for in-place \r updates).
    func writeStdout(_ string: String) {
        FileHandle.standardOutput.write(Data(string.utf8))
    }

    /// Build a fixed-width ASCII progress bar for download display.
    private static func progressBar(fraction: Double, width: Int = 16) -> String {
        let filled = min(width, Int(fraction * Double(width)))
        let empty = width - filled
        return "[" + String(repeating: "█", count: filled) + String(repeating: "░", count: empty) + "]"
    }
}
