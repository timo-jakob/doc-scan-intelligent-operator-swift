import Foundation
import AppKit

/// Result of invoice detection and data extraction
public struct InvoiceData {
    public let isInvoice: Bool
    public let date: Date?
    public let company: String?

    public init(isInvoice: Bool, date: Date? = nil, company: String? = nil) {
        self.isInvoice = isInvoice
        self.date = date
        self.company = company
    }
}

/// Detects invoices and extracts key information using Vision-Language Models
public class InvoiceDetector {
    private let modelManager: ModelManager
    private let config: Configuration

    public init(config: Configuration) {
        self.config = config
        self.modelManager = ModelManager(config: config)
    }

    /// Analyze a PDF and extract invoice information
    public func analyze(pdfPath: String) async throws -> InvoiceData {
        // Validate PDF
        try PDFUtils.validatePDF(at: pdfPath)

        // Convert first page to image
        if config.verbose {
            print("Converting PDF to image...")
        }
        let image = try PDFUtils.pdfToImage(at: pdfPath, dpi: config.pdfDPI)

        // Detect if document is an invoice
        if config.verbose {
            print("Detecting invoice...")
        }
        let isInvoice = try await detectInvoice(image: image)

        guard isInvoice else {
            return InvoiceData(isInvoice: false)
        }

        // Extract invoice date and company
        if config.verbose {
            print("Extracting invoice data...")
        }
        let (date, company) = try await extractInvoiceData(image: image)

        return InvoiceData(isInvoice: true, date: date, company: company)
    }

    /// Detect if an image contains an invoice
    private func detectInvoice(image: NSImage) async throws -> Bool {
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

    /// Extract invoice date and company name
    private func extractInvoiceData(image: NSImage) async throws -> (Date?, String?) {
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

        if config.verbose {
            print("Extracted date: \(date?.description ?? "nil")")
            print("Extracted company: \(company ?? "nil")")
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
