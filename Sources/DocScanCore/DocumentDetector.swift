@preconcurrency import AppKit // TODO: Remove when NSImage is Sendable-annotated
import Foundation

// MARK: - Categorization Method

/// The method used for document categorization
public enum CategorizationMethod: Equatable, Sendable {
    case vlm
    case vlmTimeout
    case vlmError
    case ocr
    case ocrTimeout
    case pdf
}

// MARK: - Categorization Results (Phase 1: VLM + OCR in parallel)

/// Result of document categorization from a single method
public struct CategorizationResult: Equatable, Sendable {
    public let isMatch: Bool // Whether document matches the target type
    public let confidence: ConfidenceLevel
    public let method: CategorizationMethod
    public let reason: String? // Optional explanation

    public init(
        isMatch: Bool,
        confidence: ConfidenceLevel = .high,
        method: CategorizationMethod,
        reason: String? = nil
    ) {
        self.isMatch = isMatch
        self.confidence = confidence
        self.method = method
        self.reason = reason
    }

    /// Full display label for the method (e.g., "VLM (Vision Language Model)")
    public var displayLabel: String {
        switch method {
        case .vlm: "VLM (Vision Language Model)"
        case .vlmTimeout: "VLM (Vision Language Model - Timeout)"
        case .vlmError: "VLM (Vision Language Model - Error)"
        case .ocr: "OCR (Vision Framework)"
        case .ocrTimeout: "OCR (Vision Framework - Timeout)"
        case .pdf: "PDF (Direct Text Extraction)"
        }
    }

    /// True when this result represents a timeout rather than an actual categorisation decision.
    public var isTimedOut: Bool {
        method == .vlmTimeout || method == .ocrTimeout
    }

    /// Short display label for inline messages (e.g., "VLM", "PDF text", "Vision OCR")
    public var shortDisplayLabel: String {
        switch method {
        case .vlm: "VLM"
        case .vlmTimeout: "VLM (timeout)"
        case .vlmError: "VLM (error)"
        case .ocr: "Vision OCR"
        case .ocrTimeout: "OCR (timeout)"
        case .pdf: "PDF text"
        }
    }
}

/// Comparison result for categorization phase
public struct CategorizationVerification: Equatable, Sendable {
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
public actor DocumentDetector {
    private let vlmProvider: any VLMProvider
    private let ocrEngine: OCREngine
    private let textLLM: any TextLLMProviding
    nonisolated let config: Configuration
    public nonisolated let documentType: DocumentType

    // Cache the image and OCR text between phases
    private var cachedImage: NSImage?
    private var cachedOCRText: String?
    private var cachedPDFPath: String?
    private var usedDirectExtraction: Bool = false

    /// Initialize with optional dependency injection for VLM and TextLLM providers.
    /// Defaults are created automatically when not supplied.
    public init(
        config: Configuration,
        documentType: DocumentType = .invoice,
        vlmProvider: (any VLMProvider)? = nil,
        textLLM: (any TextLLMProviding)? = nil
    ) {
        self.config = config
        self.documentType = documentType
        self.vlmProvider = vlmProvider ?? ModelManager(config: config)
        ocrEngine = OCREngine(config: config)
        self.textLLM = textLLM ?? TextLLMManager(config: config)
    }
}

extension DocumentDetector {
    /// Timeout for individual categorization methods (VLM or OCR)
    private static let categorizationTimeoutSeconds: TimeInterval = 30.0

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

        // Capture Sendable dependencies for true parallel execution outside actor isolation
        let vlmProv = vlmProvider
        let ocrEng = ocrEngine
        let docType = documentType
        let cfg = config

        // Run VLM and OCR truly in parallel (nonisolated static methods avoid actor hop)
        async let vlmResult = Self.performVLMCategorization(
            image: image, vlmProvider: vlmProv, documentType: docType, config: cfg
        )
        async let ocrResult = Self.performOCRCategorization(
            image: image, directText: directText, ocrEngine: ocrEng,
            documentType: docType, config: cfg
        )

        let vlm = await vlmResult
        let (ocr, ocrText) = try await ocrResult

        // Cache OCR text from parallel task for Phase 2
        if let ocrText, cachedOCRText == nil {
            cachedOCRText = ocrText
        }

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

    // MARK: - Parallel Categorization Helpers (nonisolated for true concurrency)

    /// Run VLM categorization outside actor isolation for true parallel execution.
    private nonisolated static func performVLMCategorization(
        image: NSImage,
        vlmProvider: any VLMProvider,
        documentType: DocumentType,
        config: Configuration
    ) async -> CategorizationResult {
        do {
            return try await TimeoutError.withTimeout(seconds: categorizationTimeoutSeconds) {
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
                let confidence: ConfidenceLevel = (lowercased == "yes" || lowercased == "no") ? .high : .medium

                if config.verbose {
                    let typeName = documentType.displayName.lowercased()
                    print("VLM: Is \(typeName) = \(isMatch) (confidence: \(confidence))")
                }

                return CategorizationResult(
                    isMatch: isMatch, confidence: confidence,
                    method: .vlm, reason: response
                )
            }
        } catch is TimeoutError {
            if config.verbose {
                print("⏱️  VLM timed out after \(Int(categorizationTimeoutSeconds)) seconds")
            }
            return CategorizationResult(
                isMatch: false, confidence: .low,
                method: .vlmTimeout, reason: "Timed out"
            )
        } catch {
            if config.verbose { print("VLM categorization failed: \(error)") }
            return CategorizationResult(
                isMatch: false, confidence: .low,
                method: .vlmError, reason: error.localizedDescription
            )
        }
    }

    /// Run OCR categorization outside actor isolation for true parallel execution.
    /// Returns the result and optionally the extracted OCR text (to cache for Phase 2).
    private nonisolated static func performOCRCategorization(
        image: NSImage,
        directText: String?,
        ocrEngine: OCREngine,
        documentType: DocumentType,
        config: Configuration
    ) async throws -> (CategorizationResult, String?) {
        do {
            return try await TimeoutError.withTimeout(seconds: categorizationTimeoutSeconds) {
                if let text = directText {
                    // Direct text already cached by tryDirectTextExtraction
                    let result = OCREngine.detectKeywords(for: documentType, from: text)
                    if config.verbose {
                        print("PDF: Using direct text extraction for categorization...")
                        let typeName = documentType.displayName.lowercased()
                        print("PDF: Is \(typeName) = \(result.isMatch) (confidence: \(result.confidence))")
                    }
                    return (CategorizationResult(
                        isMatch: result.isMatch, confidence: result.confidence,
                        method: .pdf, reason: result.reason
                    ), nil)
                } else {
                    if config.verbose { print("OCR: Starting Vision OCR (scanned document)...") }
                    let text = try ocrEngine.extractText(from: image)
                    if config.verbose {
                        print("OCR: Extracted \(text.count) characters")
                    }
                    let result = ocrEngine.detectKeywords(for: documentType, from: text)
                    if config.verbose {
                        let typeName = documentType.displayName.lowercased()
                        print("OCR: Is \(typeName) = \(result.isMatch) (confidence: \(result.confidence))")
                    }
                    return (CategorizationResult(
                        isMatch: result.isMatch, confidence: result.confidence,
                        method: .ocr, reason: result.reason
                    ), text)
                }
            }
        } catch is TimeoutError {
            if config.verbose {
                print("⏱️  OCR timed out after \(Int(categorizationTimeoutSeconds)) seconds")
            }
            return (CategorizationResult(
                isMatch: false, confidence: .low,
                method: .ocrTimeout, reason: "Timed out"
            ), nil)
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

    // MARK: - Direct Text Categorization (public for testing)

    /// Categorize using direct PDF text (no OCR needed).
    /// Nonisolated because it only accesses let properties and uses static methods.
    public nonisolated func categorizeWithDirectText(_ text: String) -> CategorizationResult {
        let result = OCREngine.detectKeywords(for: documentType, from: text)
        if config.verbose {
            let typeName = documentType.displayName.lowercased()
            print("PDF: Is \(typeName) = \(result.isMatch) (confidence: \(result.confidence))")
        }
        return CategorizationResult(
            isMatch: result.isMatch, confidence: result.confidence,
            method: .pdf, reason: result.reason
        )
    }
}
