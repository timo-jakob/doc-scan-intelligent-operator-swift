import AppKit
import Foundation

// MARK: - Categorization Results (Phase 1: VLM + OCR in parallel)

/// Result of document categorization from a single method
public struct CategorizationResult: Sendable {
    public let isMatch: Bool // Whether document matches the target type
    public let confidence: String // "high", "medium", "low"
    public let method: String // "VLM", "OCR", or "PDF"
    public let reason: String? // Optional explanation

    public init(isMatch: Bool, confidence: String = "high", method: String, reason: String? = nil) {
        self.isMatch = isMatch
        self.confidence = confidence
        self.method = method
        self.reason = reason
    }

    /// Full display label for the method (e.g., "VLM (Vision Language Model)")
    public var displayLabel: String {
        if method.hasPrefix("VLM") {
            if method.contains("timeout") {
                return "VLM (Vision Language Model - Timeout)"
            } else if method.contains("error") {
                return "VLM (Vision Language Model - Error)"
            }
            return "VLM (Vision Language Model)"
        } else if method.hasPrefix("PDF") {
            return "PDF (Direct Text Extraction)"
        } else if method.hasPrefix("OCR") {
            if method.contains("timeout") {
                return "OCR (Vision Framework - Timeout)"
            }
            return "OCR (Vision Framework)"
        }
        return method
    }

    /// True when this result represents a timeout rather than an actual categorisation decision.
    public var isTimedOut: Bool {
        method.contains("timeout")
    }

    /// Short display label for inline messages (e.g., "VLM", "PDF text", "Vision OCR")
    public var shortDisplayLabel: String {
        if method.hasPrefix("VLM") {
            if method.contains("timeout") {
                return "VLM (timeout)"
            } else if method.contains("error") {
                return "VLM (error)"
            }
            return "VLM"
        } else if method.hasPrefix("PDF") {
            return "PDF text"
        } else if method.hasPrefix("OCR") {
            if method.contains("timeout") {
                return "OCR (timeout)"
            }
            return "Vision OCR"
        }
        return method
    }
}

/// Comparison result for categorization phase
public struct CategorizationVerification {
    public let vlmResult: CategorizationResult
    public let ocrResult: CategorizationResult
    public let bothAgree: Bool
    public let agreedIsMatch: Bool? // Whether both agree document matches target type

    public init(vlmResult: CategorizationResult, ocrResult: CategorizationResult) {
        self.vlmResult = vlmResult
        self.ocrResult = ocrResult
        bothAgree = vlmResult.isMatch == ocrResult.isMatch
        agreedIsMatch = bothAgree ? vlmResult.isMatch : nil
    }
}

/// Detects documents of a specific type and extracts key information using two-phase approach:
/// Phase 1: Categorization (VLM + OCR in parallel) - Does this match the document type?
/// Phase 2: Data Extraction (OCR+TextLLM only) - Extract date and secondary field
public class DocumentDetector {
    private let vlmProvider: VLMProvider
    private let ocrEngine: OCREngine
    private let textLLM: TextLLMManager
    let config: Configuration
    public let documentType: DocumentType

    // Cache the image and OCR text between phases
    private var cachedImage: NSImage?
    private var cachedOCRText: String?
    private var cachedPDFPath: String?
    private var usedDirectExtraction: Bool = false

    /// Initialize with default ModelManager for a specific document type
    public init(config: Configuration, documentType: DocumentType = .invoice) {
        self.config = config
        self.documentType = documentType
        vlmProvider = ModelManager(config: config)
        ocrEngine = OCREngine(config: config)
        textLLM = TextLLMManager(config: config)
    }

    /// Initialize with custom VLM provider (for testing/dependency injection)
    public init(config: Configuration, documentType: DocumentType = .invoice, vlmProvider: VLMProvider) {
        self.config = config
        self.documentType = documentType
        self.vlmProvider = vlmProvider
        ocrEngine = OCREngine(config: config)
        textLLM = TextLLMManager(config: config)
    }

    /// Initialize with pre-loaded VLM provider and TextLLM manager (for startup preloading)
    public init(
        config: Configuration,
        documentType: DocumentType = .invoice,
        vlmProvider: VLMProvider,
        textLLM: TextLLMManager
    ) {
        self.config = config
        self.documentType = documentType
        self.vlmProvider = vlmProvider
        ocrEngine = OCREngine(config: config)
        self.textLLM = textLLM
    }
}

extension DocumentDetector {
    // MARK: - Phase 1: Categorization (VLM + OCR in parallel)

    /// Categorize a PDF - determine if it's an invoice using VLM + OCR in parallel
    public func categorize(pdfPath: String) async throws -> CategorizationVerification {
        // Validate PDF and prepare image
        try PDFUtils.validatePDF(at: pdfPath)
        cachedPDFPath = pdfPath
        usedDirectExtraction = false

        let directText = tryDirectTextExtraction(from: pdfPath)

        if config.verbose { print("Converting PDF to image...") }
        let image = try PDFUtils.pdfToImage(
            at: pdfPath, dpi: config.pdfDPI, verbose: config.verbose
        )
        cachedImage = image

        if config.verbose {
            print("Running categorization (VLM + OCR in parallel)...")
        }

        // Run VLM and OCR in parallel, await with timeouts
        let vlm = await runVLMCategorization(image: image)
        let ocr = try await runOCRCategorization(
            image: image, directText: directText
        )

        let verification = CategorizationVerification(vlmResult: vlm, ocrResult: ocr)
        logVerificationResult(verification)
        return verification
    }

    /// Try direct PDF text extraction (faster for searchable PDFs)
    private func tryDirectTextExtraction(from pdfPath: String) -> String? {
        if config.verbose { print("Checking for extractable text in PDF...") }

        guard let text = PDFUtils.extractText(from: pdfPath, verbose: config.verbose),
              text.count >= PDFUtils.minimumTextLength
        else { return nil }

        cachedOCRText = text
        usedDirectExtraction = true
        if config.verbose {
            print("✅ Using direct PDF text extraction (\(text.count) chars)")
        }
        return text
    }

    /// Run VLM categorization with timeout and error handling
    private func runVLMCategorization(image: NSImage) async -> CategorizationResult {
        let timeoutSeconds: TimeInterval = 30.0
        let vlmTask = Task { try await self.categorizeWithVLM(image: image) }

        do {
            return try await withTimeout(seconds: timeoutSeconds) {
                try await vlmTask.value
            }
        } catch is TimeoutError {
            if config.verbose {
                print("⏱️  VLM timed out after \(Int(timeoutSeconds)) seconds")
            }
            vlmTask.cancel()
            return CategorizationResult(
                isMatch: false, confidence: "low",
                method: "VLM (timeout)", reason: "Timed out"
            )
        } catch {
            if config.verbose { print("VLM categorization failed: \(error)") }
            return CategorizationResult(
                isMatch: false, confidence: "low",
                method: "VLM (error)", reason: error.localizedDescription
            )
        }
    }

    /// Run OCR categorization with timeout
    private func runOCRCategorization(
        image: NSImage,
        directText: String?
    ) async throws -> CategorizationResult {
        let timeoutSeconds: TimeInterval = 30.0
        let ocrTask = Task {
            if let text = directText {
                self.categorizeWithDirectText(text)
            } else {
                try await self.categorizeWithOCR(image: image)
            }
        }

        do {
            return try await withTimeout(seconds: timeoutSeconds) {
                try await ocrTask.value
            }
        } catch is TimeoutError {
            if config.verbose {
                print("⏱️  OCR timed out after \(Int(timeoutSeconds)) seconds")
            }
            ocrTask.cancel()
            return CategorizationResult(
                isMatch: false, confidence: "low",
                method: "OCR (timeout)", reason: "Timed out"
            )
        }
    }

    /// Log the verification result in verbose mode
    private func logVerificationResult(_ verification: CategorizationVerification) {
        guard config.verbose else { return }
        let typeName = documentType.displayName.lowercased()
        if verification.bothAgree {
            let match = verification.agreedIsMatch == true
            let desc = match ? "IS a \(typeName)" : "is NOT a \(typeName)"
            print("✅ VLM and OCR agree: Document \(desc)")
        } else {
            let vlmSays = verification.vlmResult.isMatch ? typeName : "not \(typeName)"
            let ocrSays = verification.ocrResult.isMatch ? typeName : "not \(typeName)"
            print("⚠️  Categorization conflict: VLM says \(vlmSays), OCR says \(ocrSays)")
        }
    }

    // MARK: - Phase 2: Data Extraction (OCR+TextLLM only)

    /// Extract document data using OCR+TextLLM only (call after categorization confirms document type)
    public func extractData() async throws -> ExtractionResult {
        guard let ocrText = cachedOCRText else {
            throw DocScanError.extractionFailed("No OCR text available. Call categorize() first.")
        }

        if config.verbose {
            print("Extracting \(documentType.displayName.lowercased()) data (OCR+TextLLM)...")
        }

        // Use TextLLM to extract date and secondary field from cached OCR text
        let result = try await textLLM.extractData(for: documentType, from: ocrText)

        if config.verbose {
            let fieldName = documentType == .invoice ? "Company" : "Doctor"
            print("Extracted data:")
            print("  Date: \(result.date?.description ?? "not found")")
            print("  \(fieldName): \(result.secondaryField ?? "not found")")
            if documentType == .prescription {
                print("  Patient: \(result.patientName ?? "not found")")
            }
        }

        return ExtractionResult(
            date: result.date,
            secondaryField: result.secondaryField,
            patientName: result.patientName
        )
    }

    // MARK: - VLM Categorization

    /// Categorize using VLM - simple yes/no document type detection
    func categorizeWithVLM(image: NSImage) async throws -> CategorizationResult {
        if config.verbose {
            let typeName = documentType.displayName.lowercased()
            print("VLM: Starting categorization for \(typeName)...")
        }

        let response = try await vlmProvider.generateFromImage(
            image, prompt: documentType.vlmPrompt
        )
        if config.verbose { print("VLM response: \(response)") }

        let lowercased = response.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let isMatch = lowercased.contains("yes") || lowercased.hasPrefix("ja")
        let confidence = (lowercased == "yes" || lowercased == "no") ? "high" : "medium"

        if config.verbose {
            let typeName = documentType.displayName.lowercased()
            print("VLM: Is \(typeName) = \(isMatch) (confidence: \(confidence))")
        }

        return CategorizationResult(
            isMatch: isMatch, confidence: confidence,
            method: "VLM", reason: response
        )
    }

    // MARK: - Text Categorization

    /// Categorize using direct PDF text (no OCR needed)
    /// Internal access for testability
    func categorizeWithDirectText(_ text: String) -> CategorizationResult {
        if config.verbose {
            print("PDF: Using direct text extraction for categorization...")
            print("PDF: Text length: \(text.count) characters")
            print("PDF: Text preview: \(String(text.prefix(500)))")
        }

        let result = ocrEngine.detectKeywords(for: documentType, from: text)

        if config.verbose {
            let typeName = documentType.displayName.lowercased()
            print("PDF: Is \(typeName) = \(result.isMatch) (confidence: \(result.confidence))")
            if let reason = result.reason { print("PDF: Reason: \(reason)") }
        }

        return CategorizationResult(
            isMatch: result.isMatch, confidence: result.confidence,
            method: "PDF", reason: result.reason
        )
    }

    /// Categorize using Vision OCR (fallback for scanned documents)
    func categorizeWithOCR(image: NSImage) async throws -> CategorizationResult {
        if config.verbose { print("OCR: Starting Vision OCR (scanned document)...") }

        let text = try await ocrEngine.extractText(from: image)
        cachedOCRText = text

        if config.verbose {
            print("OCR: Extracted \(text.count) characters")
            print("OCR: Text preview: \(String(text.prefix(500)))")
        }

        let result = ocrEngine.detectKeywords(for: documentType, from: text)

        if config.verbose {
            let typeName = documentType.displayName.lowercased()
            print("OCR: Is \(typeName) = \(result.isMatch) (confidence: \(result.confidence))")
            if let reason = result.reason { print("OCR: Reason: \(reason)") }
        }

        return CategorizationResult(
            isMatch: result.isMatch, confidence: result.confidence,
            method: "OCR", reason: result.reason
        )
    }

    // MARK: - Helper Methods

    /// Execute an async operation with a timeout
    func withTimeout<T>(
        seconds: TimeInterval,
        operation: @escaping () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await operation() }
            group.addTask {
                let nanoseconds = UInt64(seconds * 1_000_000_000)
                try await Task.sleep(nanoseconds: nanoseconds)
                throw TimeoutError()
            }
            guard let result = try await group.next() else {
                group.cancelAll()
                throw TimeoutError()
            }
            group.cancelAll()
            return result
        }
    }
}
