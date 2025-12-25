import Foundation
import AppKit

// MARK: - Categorization Results (Phase 1: VLM + OCR in parallel)

/// Result of invoice categorization from a single method
public struct CategorizationResult: Sendable {
    public let isInvoice: Bool
    public let confidence: String // "high", "medium", "low"
    public let method: String // "VLM" or "OCR"
    public let reason: String? // Optional explanation

    public init(isInvoice: Bool, confidence: String = "high", method: String, reason: String? = nil) {
        self.isInvoice = isInvoice
        self.confidence = confidence
        self.method = method
        self.reason = reason
    }
}

/// Comparison result for categorization phase
public struct CategorizationVerification {
    public let vlmResult: CategorizationResult
    public let ocrResult: CategorizationResult
    public let bothAgree: Bool
    public let agreedIsInvoice: Bool?

    public init(vlmResult: CategorizationResult, ocrResult: CategorizationResult) {
        self.vlmResult = vlmResult
        self.ocrResult = ocrResult
        self.bothAgree = vlmResult.isInvoice == ocrResult.isInvoice
        self.agreedIsInvoice = bothAgree ? vlmResult.isInvoice : nil
    }
}

// MARK: - Extraction Results (Phase 2: OCR+TextLLM only)

/// Result of data extraction (OCR+TextLLM only)
public struct ExtractionResult: Sendable {
    public let date: Date?
    public let company: String?

    public init(date: Date?, company: String?) {
        self.date = date
        self.company = company
    }
}

// MARK: - Final Invoice Data

/// Final result combining categorization and extraction
public struct InvoiceData {
    public let isInvoice: Bool
    public let date: Date?
    public let company: String?
    public let categorization: CategorizationVerification?

    public init(isInvoice: Bool, date: Date?, company: String?, categorization: CategorizationVerification? = nil) {
        self.isInvoice = isInvoice
        self.date = date
        self.company = company
        self.categorization = categorization
    }
}

/// Detects invoices and extracts key information using two-phase approach:
/// Phase 1: Categorization (VLM + OCR in parallel) - Is this an invoice?
/// Phase 2: Data Extraction (OCR+TextLLM only) - Extract date and company
public class InvoiceDetector {
    private let modelManager: ModelManager
    private let ocrEngine: OCREngine
    private let config: Configuration

    // Cache the image and OCR text between phases
    private var cachedImage: NSImage?
    private var cachedOCRText: String?

    public init(config: Configuration) {
        self.config = config
        self.modelManager = ModelManager(config: config)
        self.ocrEngine = OCREngine(config: config)
    }

    // MARK: - Phase 1: Categorization (VLM + OCR in parallel)

    /// Categorize a PDF - determine if it's an invoice using VLM + OCR in parallel
    public func categorize(pdfPath: String) async throws -> CategorizationVerification {
        // Validate PDF
        try PDFUtils.validatePDF(at: pdfPath)

        // Convert first page to image
        if config.verbose {
            print("Converting PDF to image...")
        }
        let image = try PDFUtils.pdfToImage(at: pdfPath, dpi: config.pdfDPI)
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

        // OCR categorization task (also caches the OCR text for phase 2)
        let ocrTask = Task {
            try await self.categorizeWithOCR(image: image)
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
            vlm = CategorizationResult(isInvoice: false, confidence: "low", method: "VLM (timeout)", reason: "Timed out")
        } catch {
            if config.verbose {
                print("VLM categorization failed: \(error)")
            }
            vlm = CategorizationResult(isInvoice: false, confidence: "low", method: "VLM (error)", reason: error.localizedDescription)
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
            ocr = CategorizationResult(isInvoice: false, confidence: "low", method: "OCR (timeout)", reason: "Timed out")
        } catch {
            if config.verbose {
                print("OCR categorization failed: \(error)")
            }
            throw error
        }

        // Compare results
        let verification = CategorizationVerification(vlmResult: vlm, ocrResult: ocr)

        if config.verbose {
            if verification.bothAgree {
                let result = verification.agreedIsInvoice == true ? "IS an invoice" : "is NOT an invoice"
                print("✅ VLM and OCR agree: Document \(result)")
            } else {
                print("⚠️  Categorization conflict: VLM says \(vlm.isInvoice ? "invoice" : "not invoice"), OCR says \(ocr.isInvoice ? "invoice" : "not invoice")")
            }
        }

        return verification
    }

    // MARK: - Phase 2: Data Extraction (OCR+TextLLM only)

    /// Extract invoice data using OCR+TextLLM only (call after categorization confirms it's an invoice)
    public func extractData() async throws -> ExtractionResult {
        guard let ocrText = cachedOCRText else {
            throw DocScanError.extractionFailed("No OCR text available. Call categorize() first.")
        }

        if config.verbose {
            print("Extracting invoice data (OCR+TextLLM)...")
        }

        // Use TextLLM to extract date and company from cached OCR text
        let (date, company) = try await ocrEngine.extractDateAndCompany(from: ocrText)

        if config.verbose {
            print("Extracted data:")
            print("  Date: \(date?.description ?? "not found")")
            print("  Company: \(company ?? "not found")")
        }

        return ExtractionResult(date: date, company: company)
    }

    // MARK: - VLM Categorization

    /// Categorize using VLM - simple yes/no invoice detection
    private func categorizeWithVLM(image: NSImage) async throws -> CategorizationResult {
        if config.verbose {
            print("VLM: Starting categorization...")
        }

        let prompt = """
        Look at this document image carefully.

        Is this document an INVOICE, BILL, or RECEIPT?

        Look for these indicators:
        - Words like "Rechnung", "Invoice", "Facture", "Faktura", "Bill", "Receipt"
        - Invoice number or receipt number
        - Itemized charges with prices
        - Total amount due
        - Payment terms or due date

        Answer with ONLY one word: YES or NO
        """

        let response = try await modelManager.generateFromImage(image, prompt: prompt)

        if config.verbose {
            print("VLM response: \(response)")
        }

        // Parse response - look for yes/no
        let lowercased = response.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let isInvoice = lowercased.contains("yes") || lowercased.hasPrefix("ja")
        let confidence = (lowercased == "yes" || lowercased == "no") ? "high" : "medium"

        if config.verbose {
            print("VLM: Is invoice = \(isInvoice) (confidence: \(confidence))")
        }

        return CategorizationResult(isInvoice: isInvoice, confidence: confidence, method: "VLM", reason: response)
    }

    // MARK: - OCR Categorization

    /// Categorize using OCR keyword detection
    private func categorizeWithOCR(image: NSImage) async throws -> CategorizationResult {
        if config.verbose {
            print("OCR: Starting categorization...")
        }

        // Extract text using Vision OCR
        let text = try await ocrEngine.extractText(from: image)
        cachedOCRText = text // Cache for phase 2

        if config.verbose {
            print("OCR: Extracted \(text.count) characters")
        }

        // Use keyword-based detection
        let (isInvoice, confidence, reason) = ocrEngine.detectInvoiceKeywords(from: text)

        if config.verbose {
            print("OCR: Is invoice = \(isInvoice) (confidence: \(confidence))")
            if let reason = reason {
                print("OCR: Reason: \(reason)")
            }
        }

        return CategorizationResult(isInvoice: isInvoice, confidence: confidence, method: "OCR", reason: reason)
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
            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }

    /// Generate filename from invoice data
    public func generateFilename(from data: InvoiceData) -> String? {
        guard data.isInvoice else { return nil }
        guard let date = data.date, let company = data.company else { return nil }

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = config.dateFormat
        let dateString = dateFormatter.string(from: date)

        return config.filenamePattern
            .replacingOccurrences(of: "{date}", with: dateString)
            .replacingOccurrences(of: "{company}", with: company)
    }
}
