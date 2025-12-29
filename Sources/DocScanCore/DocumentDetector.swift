import Foundation
import AppKit

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
        self.bothAgree = vlmResult.isMatch == ocrResult.isMatch
        self.agreedIsMatch = bothAgree ? vlmResult.isMatch : nil
    }
}

// MARK: - Extraction Results (Phase 2: OCR+TextLLM only)

/// Result of data extraction (OCR+TextLLM only)
/// Contains date and a secondary field (company for invoices, doctor for prescriptions)
public struct ExtractionResult: Sendable {
    public let date: Date?
    public let secondaryField: String? // company, doctor, etc. depending on document type
    public let patientName: String? // patient first name (for prescriptions)

    public init(date: Date?, secondaryField: String?, patientName: String? = nil) {
        self.date = date
        self.secondaryField = secondaryField
        self.patientName = patientName
    }
}

// MARK: - Final Document Data

/// Final result combining categorization and extraction
public struct DocumentData {
    public let documentType: DocumentType
    public let isMatch: Bool // Whether document matches the target type
    public let date: Date?
    public let secondaryField: String? // company, doctor, etc.
    public let patientName: String? // patient first name (for prescriptions)
    public let categorization: CategorizationVerification?

    public init(
        documentType: DocumentType,
        isMatch: Bool,
        date: Date?,
        secondaryField: String?,
        patientName: String? = nil,
        categorization: CategorizationVerification? = nil
    ) {
        self.documentType = documentType
        self.isMatch = isMatch
        self.date = date
        self.secondaryField = secondaryField
        self.patientName = patientName
        self.categorization = categorization
    }
}

/// Detects documents of a specific type and extracts key information using two-phase approach:
/// Phase 1: Categorization (VLM + OCR in parallel) - Does this match the document type?
/// Phase 2: Data Extraction (OCR+TextLLM only) - Extract date and secondary field
public class DocumentDetector {
    private let vlmProvider: VLMProvider
    private let ocrEngine: OCREngine
    private let textLLM: TextLLMManager
    private let config: Configuration
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
        self.vlmProvider = ModelManager(config: config)
        self.ocrEngine = OCREngine(config: config)
        self.textLLM = TextLLMManager(config: config)
    }

    /// Initialize with custom VLM provider (for testing/dependency injection)
    public init(config: Configuration, documentType: DocumentType = .invoice, vlmProvider: VLMProvider) {
        self.config = config
        self.documentType = documentType
        self.vlmProvider = vlmProvider
        self.ocrEngine = OCREngine(config: config)
        self.textLLM = TextLLMManager(config: config)
    }
}

extension DocumentDetector {

    // MARK: - Phase 1: Categorization (VLM + OCR in parallel)

    /// Categorize a PDF - determine if it's an invoice using VLM + OCR in parallel
    public func categorize(pdfPath: String) async throws -> CategorizationVerification {
        // Validate PDF
        try PDFUtils.validatePDF(at: pdfPath)

        // Cache the PDF path for OCR
        cachedPDFPath = pdfPath
        usedDirectExtraction = false

        // Try direct PDF text extraction first (faster and more accurate for searchable PDFs)
        if config.verbose {
            print("Checking for extractable text in PDF...")
        }

        var directText: String? = nil
        if let text = PDFUtils.extractText(from: pdfPath, verbose: config.verbose),
           text.count >= PDFUtils.minimumTextLength {
            directText = text
            cachedOCRText = text
            usedDirectExtraction = true
            if config.verbose {
                print("✅ Using direct PDF text extraction (\(text.count) chars) - faster and more accurate")
            }
        }

        // Convert first page to image (needed for VLM, and for OCR fallback)
        if config.verbose {
            print("Converting PDF to image...")
        }
        let image = try PDFUtils.pdfToImage(at: pdfPath, dpi: config.pdfDPI, verbose: config.verbose)
        cachedImage = image

        // Run both VLM and OCR categorization in parallel
        if config.verbose {
            print("Running categorization (VLM + OCR in parallel)...")
        }

        // Timeout duration: 30 seconds
        let timeoutDuration: TimeInterval = 30.0

        // VLM categorization task
        let vlmTask = Task {
            try await self.categorizeWithVLM(image: image)
        }

        // OCR categorization task
        // If we have direct text, use it; otherwise fall back to Vision OCR
        let ocrTask = Task {
            if let text = directText {
                return self.categorizeWithDirectText(text)
            } else {
                return try await self.categorizeWithOCR(image: image)
            }
        }

        // Handle VLM with timeout
        let vlm: CategorizationResult
        do {
            vlm = try await withTimeout(seconds: timeoutDuration) {
                try await vlmTask.value
            }
        } catch is TimeoutError {
            if config.verbose {
                print("⏱️  VLM timed out after \(Int(timeoutDuration)) seconds")
            }
            vlmTask.cancel()
            vlm = CategorizationResult(isMatch: false, confidence: "low", method: "VLM (timeout)", reason: "Timed out")
        } catch {
            if config.verbose {
                print("VLM categorization failed: \(error)")
            }
            vlm = CategorizationResult(isMatch: false, confidence: "low", method: "VLM (error)", reason: error.localizedDescription)
        }

        // Handle OCR with timeout
        let ocr: CategorizationResult
        do {
            ocr = try await withTimeout(seconds: timeoutDuration) {
                try await ocrTask.value
            }
        } catch is TimeoutError {
            if config.verbose {
                print("⏱️  OCR timed out after \(Int(timeoutDuration)) seconds")
            }
            ocrTask.cancel()
            ocr = CategorizationResult(isMatch: false, confidence: "low", method: "OCR (timeout)", reason: "Timed out")
        } catch {
            if config.verbose {
                print("OCR categorization failed: \(error)")
            }
            throw error
        }

        // Compare results
        let verification = CategorizationVerification(vlmResult: vlm, ocrResult: ocr)

        if config.verbose {
            let typeName = documentType.displayName.lowercased()
            if verification.bothAgree {
                let result = verification.agreedIsMatch == true ? "IS a \(typeName)" : "is NOT a \(typeName)"
                print("✅ VLM and OCR agree: Document \(result)")
            } else {
                print("⚠️  Categorization conflict: VLM says \(vlm.isMatch ? typeName : "not \(typeName)"), OCR says \(ocr.isMatch ? typeName : "not \(typeName)")")
            }
        }

        return verification
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

        return ExtractionResult(date: result.date, secondaryField: result.secondaryField, patientName: result.patientName)
    }

    // MARK: - VLM Categorization

    /// Categorize using VLM - simple yes/no document type detection
    private func categorizeWithVLM(image: NSImage) async throws -> CategorizationResult {
        if config.verbose {
            print("VLM: Starting categorization for \(documentType.displayName.lowercased())...")
        }

        let prompt = documentType.vlmPrompt

        let response = try await vlmProvider.generateFromImage(image, prompt: prompt)

        if config.verbose {
            print("VLM response: \(response)")
        }

        // Parse response - look for yes/no
        let lowercased = response.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let isMatch = lowercased.contains("yes") || lowercased.hasPrefix("ja")
        let confidence = (lowercased == "yes" || lowercased == "no") ? "high" : "medium"

        if config.verbose {
            print("VLM: Is \(documentType.displayName.lowercased()) = \(isMatch) (confidence: \(confidence))")
        }

        return CategorizationResult(isMatch: isMatch, confidence: confidence, method: "VLM", reason: response)
    }

    // MARK: - Text Categorization

    /// Categorize using direct PDF text (no OCR needed - faster and more accurate)
    /// Internal access for testability
    func categorizeWithDirectText(_ text: String) -> CategorizationResult {
        if config.verbose {
            print("PDF: Using direct text extraction for categorization...")
            print("PDF: Text length: \(text.count) characters")
            print("PDF: Text preview: \(String(text.prefix(500)))")
        }

        // Use keyword-based detection on the direct text
        let (isMatch, confidence, reason) = ocrEngine.detectKeywords(for: documentType, from: text)

        if config.verbose {
            print("PDF: Is \(documentType.displayName.lowercased()) = \(isMatch) (confidence: \(confidence))")
            if let reason = reason {
                print("PDF: Reason: \(reason)")
            }
        }

        return CategorizationResult(isMatch: isMatch, confidence: confidence, method: "PDF", reason: reason)
    }

    /// Categorize using Vision OCR (fallback for scanned documents)
    private func categorizeWithOCR(image: NSImage) async throws -> CategorizationResult {
        if config.verbose {
            print("OCR: Starting Vision OCR (scanned document)...")
        }

        // Extract text using Vision OCR
        let text = try await ocrEngine.extractText(from: image)
        cachedOCRText = text // Cache for phase 2

        if config.verbose {
            print("OCR: Extracted \(text.count) characters")
            print("OCR: Text preview: \(String(text.prefix(500)))")
        }

        // Use keyword-based detection
        let (isMatch, confidence, reason) = ocrEngine.detectKeywords(for: documentType, from: text)

        if config.verbose {
            print("OCR: Is \(documentType.displayName.lowercased()) = \(isMatch) (confidence: \(confidence))")
            if let reason = reason {
                print("OCR: Reason: \(reason)")
            }
        }

        return CategorizationResult(isMatch: isMatch, confidence: confidence, method: "OCR", reason: reason)
    }

    // MARK: - Helper Methods

    /// Execute an async operation with a timeout
    private func withTimeout<T>(
        seconds: TimeInterval,
        operation: @escaping () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            // Add the actual operation
            group.addTask {
                try await operation()
            }

            // Add the timeout task
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw TimeoutError()
            }

            // Wait for the first to complete
            guard let result = try await group.next() else {
                group.cancelAll()
                throw TimeoutError()
            }
            group.cancelAll()
            return result
        }
    }

    /// Generate filename from document data
    public func generateFilename(from data: DocumentData) -> String? {
        guard data.isMatch else { return nil }
        guard let date = data.date else { return nil }

        // For invoices, company is required
        if documentType == .invoice && data.secondaryField == nil {
            return nil
        }

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = config.dateFormat
        let dateString = dateFormatter.string(from: date)

        // Use document type's default pattern
        var pattern = documentType.defaultFilenamePattern
        pattern = pattern.replacingOccurrences(of: "{date}", with: dateString)

        // Replace the secondary field placeholder based on document type
        switch documentType {
        case .invoice:
            pattern = pattern.replacingOccurrences(of: "{company}", with: data.secondaryField!)
        case .prescription:
            // Handle patient name placeholder first (optional)
            // Must be processed before doctor to handle the case where both are nil
            if let patientName = data.patientName {
                pattern = pattern.replacingOccurrences(of: "{patient}", with: patientName)
            } else {
                // Remove the "für_{patient}_" part if no patient name available
                pattern = pattern.replacingOccurrences(of: "für_{patient}_", with: "")
            }
            // Handle doctor name placeholder (optional)
            if let doctor = data.secondaryField {
                pattern = pattern.replacingOccurrences(of: "{doctor}", with: doctor)
            } else {
                // Remove the "_von_{doctor}" part if no doctor name available
                pattern = pattern.replacingOccurrences(of: "_von_{doctor}", with: "")
            }
        }

        return pattern
    }
}
