import Foundation
import Vision
import AppKit

/// OCR engine using Apple's Vision framework for text recognition
public class OCREngine {
    private let config: Configuration

    public init(config: Configuration) {
        self.config = config
    }

    /// Extract text from an image using Vision OCR
    public func extractText(from image: NSImage) async throws -> String {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw DocScanError.pdfConversionFailed("Unable to convert NSImage to CGImage")
        }

        return try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error = error {
                    continuation.resume(throwing: DocScanError.extractionFailed("OCR failed: \(error.localizedDescription)"))
                    return
                }

                guard let observations = request.results as? [VNRecognizedTextObservation] else {
                    continuation.resume(throwing: DocScanError.extractionFailed("No text observations found"))
                    return
                }

                let recognizedText = observations.compactMap { observation in
                    observation.topCandidates(1).first?.string
                }.joined(separator: "\n")

                if recognizedText.isEmpty {
                    continuation.resume(throwing: DocScanError.extractionFailed("No text recognized"))
                } else {
                    continuation.resume(returning: recognizedText)
                }
            }

            // Configure for accurate text recognition
            request.recognitionLevel = .accurate
            request.recognitionLanguages = ["en-US", "de-DE", "fr-FR", "es-ES"]
            request.usesLanguageCorrection = true

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: DocScanError.extractionFailed("OCR request failed: \(error.localizedDescription)"))
            }
        }
    }

    /// Detect if text contains invoice indicators
    public func detectInvoice(from text: String) -> Bool {
        let lowercased = text.lowercased()

        // Common invoice indicators in multiple languages
        let indicators = [
            // German
            "rechnung", "rechnungsnummer", "rechnungsdatum",
            // English
            "invoice", "invoice number", "invoice date",
            // French
            "facture", "numéro de facture",
            // Spanish
            "factura", "número de factura"
        ]

        return indicators.contains { lowercased.contains($0) }
    }

    /// Extract invoice date from OCR text
    public func extractDate(from text: String) -> Date? {
        // Common date patterns
        let patterns = [
            // ISO format: 2024-12-22
            "\\b(\\d{4})-(\\d{2})-(\\d{2})\\b",
            // European format: 22.12.2024 or 22/12/2024
            "\\b(\\d{2})[./](\\d{2})[./](\\d{4})\\b",
            // US format: 12/22/2024
            "\\b(\\d{2})/(\\d{2})/(\\d{4})\\b"
        ]

        for pattern in patterns {
            if let date = extractDateWithPattern(text, pattern: pattern) {
                return date
            }
        }

        // Try to find date near common keywords
        let dateKeywords = [
            "datum:", "date:", "rechnungsdatum:", "invoice date:",
            "facture du:", "fecha:"
        ]

        for keyword in dateKeywords {
            if let range = text.range(of: keyword, options: .caseInsensitive) {
                let afterKeyword = String(text[range.upperBound...])
                let nearbyText = String(afterKeyword.prefix(30))

                for pattern in patterns {
                    if let date = extractDateWithPattern(nearbyText, pattern: pattern) {
                        return date
                    }
                }
            }
        }

        return nil
    }

    private func extractDateWithPattern(_ text: String, pattern: String) -> Date? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }

        let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))

        for match in matches {
            if let range = Range(match.range, in: text) {
                let dateString = String(text[range])
                if let date = parseDate(dateString) {
                    return date
                }
            }
        }

        return nil
    }

    private func parseDate(_ dateString: String) -> Date? {
        let formatters = [
            "yyyy-MM-dd",
            "dd.MM.yyyy",
            "dd/MM/yyyy",
            "MM/dd/yyyy"
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

    /// Extract company name from OCR text
    public func extractCompany(from text: String) -> String? {
        let lines = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        guard !lines.isEmpty else { return nil }

        // Strategy 1: Look for company indicators
        let companyKeywords = [
            "gmbh", "ag", "inc", "ltd", "llc", "corp", "corporation",
            "sarl", "s.a.", "kg", "ohg"
        ]

        for line in lines.prefix(10) { // Check first 10 lines
            let lowercased = line.lowercased()
            if companyKeywords.contains(where: { lowercased.contains($0) }) {
                return sanitizeCompanyName(line)
            }
        }

        // Strategy 2: Use first non-empty line (often company name)
        if let firstLine = lines.first, firstLine.count > 3 {
            return sanitizeCompanyName(firstLine)
        }

        return nil
    }

    private func sanitizeCompanyName(_ name: String) -> String {
        // Remove special characters problematic in filenames
        let invalidChars = CharacterSet(charactersIn: ":/\\?%*|\"<>")
        let sanitized = name.components(separatedBy: invalidChars).joined()

        // Replace multiple spaces with single space
        let singleSpaced = sanitized.replacingOccurrences(
            of: "\\s+",
            with: " ",
            options: .regularExpression
        )

        // Trim and limit length
        let trimmed = singleSpaced.trimmingCharacters(in: .whitespaces)
        return String(trimmed.prefix(50))
    }

    /// Extract all invoice data from OCR text
    public func extractInvoiceData(from text: String) -> (isInvoice: Bool, date: Date?, company: String?) {
        if config.verbose {
            print("OCR extracted text (\(text.count) characters)")
        }

        let isInvoice = detectInvoice(from: text)
        guard isInvoice else {
            return (false, nil, nil)
        }

        let date = extractDate(from: text)
        let company = extractCompany(from: text)

        if config.verbose {
            print("OCR Results:")
            print("  Is Invoice: \(isInvoice)")
            print("  Date: \(date?.description ?? "nil")")
            print("  Company: \(company ?? "nil")")
        }

        return (isInvoice, date, company)
    }
}
