import Foundation
import AppKit

/// Result of invoice detection and data extraction from a single method
public struct ExtractionResult: Sendable {
    public let isInvoice: Bool
    public let date: Date?
    public let company: String?
    public let method: String // "VLM" or "OCR"

    public init(isInvoice: Bool, date: Date?, company: String?, method: String) {
        self.isInvoice = isInvoice
        self.date = date
        self.company = company
        self.method = method
    }
}

/// Comparison result showing agreement or conflict between VLM and OCR
public struct VerificationResult {
    public let vmlResult: ExtractionResult
    public let ocrResult: ExtractionResult
    public let hasConflict: Bool
    public let conflicts: [String]

    public init(vmlResult: ExtractionResult, ocrResult: ExtractionResult) {
        self.vmlResult = vmlResult
        self.ocrResult = ocrResult

        var conflicts: [String] = []

        // Check for conflicts
        if vmlResult.isInvoice != ocrResult.isInvoice {
            conflicts.append("Invoice detection")
        }

        if vmlResult.date != ocrResult.date {
            conflicts.append("Date")
        }

        if vmlResult.company != ocrResult.company {
            conflicts.append("Company name")
        }

        self.conflicts = conflicts
        self.hasConflict = !conflicts.isEmpty
    }

    /// Get agreed-upon result if no conflicts, otherwise nil
    public var agreedResult: ExtractionResult? {
        guard !hasConflict else { return nil }
        return vmlResult
    }
}

/// Result of invoice detection and data extraction (final)
public struct InvoiceData {
    public let isInvoice: Bool
    public let date: Date?
    public let company: String?
    public let verificationResult: VerificationResult?

    public init(isInvoice: Bool, date: Date?, company: String?, verificationResult: VerificationResult? = nil) {
        self.isInvoice = isInvoice
        self.date = date
        self.company = company
        self.verificationResult = verificationResult
    }

    /// Create from extraction result
    public init(from result: ExtractionResult, verificationResult: VerificationResult? = nil) {
        self.isInvoice = result.isInvoice
        self.date = result.date
        self.company = result.company
        self.verificationResult = verificationResult
    }
}

/// Detects invoices and extracts key information using dual verification (VLM + OCR)
public class InvoiceDetector {
    private let modelManager: ModelManager
    private let ocrEngine: OCREngine
    private let config: Configuration

    public init(config: Configuration) {
        self.config = config
        self.modelManager = ModelManager(config: config)
        self.ocrEngine = OCREngine(config: config)
    }

    /// Analyze a PDF with dual verification (VLM + OCR in parallel)
    public func analyze(pdfPath: String) async throws -> VerificationResult {
        // Validate PDF
        try PDFUtils.validatePDF(at: pdfPath)

        // Convert first page to image
        if config.verbose {
            print("Converting PDF to image...")
        }
        let image = try PDFUtils.pdfToImage(at: pdfPath, dpi: config.pdfDPI)

        // Run both VLM and OCR in parallel
        if config.verbose {
            print("Running dual verification (VLM + OCR in parallel)...")
        }

        // Use Task directly to avoid sendability issues
        let vmlTask = Task {
            try await self.extractWithVLM(image: image)
        }

        let ocrTask = Task {
            try await self.extractWithOCR(image: image)
        }

        let vml = try await vmlTask.value
        let ocr = try await ocrTask.value

        // Compare results
        let verification = VerificationResult(vmlResult: vml, ocrResult: ocr)

        if config.verbose {
            if verification.hasConflict {
                print("⚠️  Conflict detected in: \(verification.conflicts.joined(separator: ", "))")
            } else {
                print("✅ VLM and OCR agree on all fields")
            }
        }

        return verification
    }

    /// Extract data using VLM
    private func extractWithVLM(image: NSImage) async throws -> ExtractionResult {
        if config.verbose {
            print("VLM: Starting analysis...")
        }

        // Detect if document is an invoice
        let isInvoice = try await detectInvoiceVLM(image: image)

        guard isInvoice else {
            if config.verbose {
                print("VLM: Not an invoice")
            }
            return ExtractionResult(isInvoice: false, date: nil, company: nil, method: "VLM")
        }

        // Extract invoice date and company
        let (date, company) = try await extractInvoiceDataVLM(image: image)

        if config.verbose {
            print("VLM Results:")
            print("  Is Invoice: \(isInvoice)")
            print("  Date: \(date?.description ?? "nil")")
            print("  Company: \(company ?? "nil")")
        }

        return ExtractionResult(isInvoice: isInvoice, date: date, company: company, method: "VLM")
    }

    /// Extract data using OCR
    private func extractWithOCR(image: NSImage) async throws -> ExtractionResult {
        if config.verbose {
            print("OCR: Starting analysis...")
        }

        let text = try await ocrEngine.extractText(from: image)
        let (isInvoice, date, company) = ocrEngine.extractInvoiceData(from: text)

        return ExtractionResult(isInvoice: isInvoice, date: date, company: company, method: "OCR")
    }

    /// Detect if an image contains an invoice using VLM
    private func detectInvoiceVLM(image: NSImage) async throws -> Bool {
        let prompt = """
        Is this document an invoice (Rechnung)?
        Answer with only 'yes' or 'no'.
        """

        let response = try await modelManager.generateFromImage(
            image,
            prompt: prompt
        )

        let normalized = response.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.contains("yes") || normalized.contains("ja")
    }

    /// Extract invoice date and company using VLM
    private func extractInvoiceDataVLM(image: NSImage) async throws -> (Date?, String?) {
        let prompt = """
        Extract the following information from this invoice:
        1. Invoice date (Rechnungsdatum): Provide in format YYYY-MM-DD
        2. Invoicing party (company name that issued the invoice)

        Respond in this exact format:
        DATE: YYYY-MM-DD
        COMPANY: Company Name

        If you cannot find the information, write "UNKNOWN" for that field.
        """

        let response = try await modelManager.generateFromImage(
            image,
            prompt: prompt
        )

        // Parse response
        let lines = response.components(separatedBy: .newlines)
        var date: Date?
        var company: String?

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("DATE:") {
                let dateString = trimmed
                    .replacingOccurrences(of: "DATE:", with: "")
                    .trimmingCharacters(in: .whitespaces)

                if dateString != "UNKNOWN" {
                    date = parseDate(dateString)
                }
            } else if trimmed.hasPrefix("COMPANY:") {
                let companyName = trimmed
                    .replacingOccurrences(of: "COMPANY:", with: "")
                    .trimmingCharacters(in: .whitespaces)

                if companyName != "UNKNOWN" {
                    company = sanitizeCompanyName(companyName)
                }
            }
        }

        return (date, company)
    }

    /// Parse date string in various formats
    private func parseDate(_ dateString: String) -> Date? {
        let formatters = [
            "yyyy-MM-dd",
            "dd.MM.yyyy",
            "MM/dd/yyyy",
            "dd/MM/yyyy"
        ].map { format -> DateFormatter in
            let formatter = DateFormatter()
            formatter.dateFormat = format
            formatter.locale = Locale(identifier: "en_US_POSIX")
            return formatter
        }

        for formatter in formatters {
            if let date = formatter.date(from: dateString) {
                return date
            }
        }

        return nil
    }

    /// Sanitize company name for use in filename
    private func sanitizeCompanyName(_ name: String) -> String {
        // Remove special characters that are problematic in filenames
        let invalidChars = CharacterSet(charactersIn: ":/\\?%*|\"<>")
        let sanitized = name.components(separatedBy: invalidChars).joined()

        // Replace multiple spaces with single space
        let singleSpaced = sanitized.replacingOccurrences(
            of: "\\s+",
            with: " ",
            options: .regularExpression
        )

        // Trim whitespace
        return singleSpaced.trimmingCharacters(in: .whitespaces)
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
