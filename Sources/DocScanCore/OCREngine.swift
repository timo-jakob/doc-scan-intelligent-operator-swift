import Foundation
import Vision
import AppKit

/// OCR engine using Apple's Vision framework for text recognition + Text-LLM for analysis
public class OCREngine {
    private let config: Configuration
    private let textLLM: TextLLMManager

    public init(config: Configuration) {
        self.config = config
        self.textLLM = TextLLMManager(config: config)
    }

    /// Extract text from an image using Vision OCR
    /// For very tall images (aspect ratio > 4:1), tiles the image to ensure full text extraction
    public func extractText(from image: NSImage) async throws -> String {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw DocScanError.pdfConversionFailed("Unable to convert NSImage to CGImage")
        }

        let width = cgImage.width
        let height = cgImage.height
        let aspectRatio = Double(height) / Double(width)

        // For very tall images, tile to work around Vision's limitations
        if aspectRatio > 4.0 {
            if config.verbose {
                print("OCR: Tall image detected (aspect ratio \(String(format: "%.1f", aspectRatio)):1), using tiled OCR")
            }
            return try await extractTextTiled(from: cgImage)
        }

        return try await extractTextSingle(from: cgImage)
    }

    /// Extract text from a single image (standard OCR)
    private func extractTextSingle(from cgImage: CGImage) async throws -> String {
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

    /// Extract text from a tall image by splitting into tiles
    private func extractTextTiled(from cgImage: CGImage) async throws -> String {
        let width = cgImage.width
        let height = cgImage.height
        let tileHeight = 800  // Tile height in pixels
        var allText = ""

        for tileY in stride(from: 0, to: height, by: tileHeight) {
            let cropHeight = min(tileHeight, height - tileY)
            let cropRect = CGRect(x: 0, y: tileY, width: width, height: cropHeight)

            guard let croppedImage = cgImage.cropping(to: cropRect) else {
                continue
            }

            do {
                let tileText = try await extractTextSingle(from: croppedImage)
                allText += tileText + "\n"
            } catch {
                // Continue with other tiles even if one fails
                if config.verbose {
                    print("OCR: Tile at y=\(tileY) failed: \(error.localizedDescription)")
                }
            }
        }

        if allText.isEmpty {
            throw DocScanError.extractionFailed("No text recognized from any tile")
        }

        return allText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Detect if text contains invoice indicators (simple boolean)
    public func detectInvoice(from text: String) -> Bool {
        let (isInvoice, _, _) = Self.detectInvoiceKeywords(from: text)
        return isInvoice
    }

    /// Detect invoice keywords with confidence and reason (instance method)
    public func detectInvoiceKeywords(from text: String) -> (isInvoice: Bool, confidence: String, reason: String?) {
        return Self.detectInvoiceKeywords(from: text)
    }

    /// Detect invoice keywords with confidence and reason (static, shared implementation)
    public static func detectInvoiceKeywords(from text: String) -> (isInvoice: Bool, confidence: String, reason: String?) {
        let lowercased = text.lowercased()

        // Strong indicators (high confidence)
        let strongIndicators = [
            "rechnungsnummer", "invoice number", "numéro de facture", "número de factura",
            "rechnungsdatum", "invoice date"
        ]

        // Medium indicators
        let mediumIndicators = [
            "rechnung", "invoice", "facture", "factura", "quittung", "receipt"
        ]

        var foundStrong: [String] = []
        var foundMedium: [String] = []

        for indicator in strongIndicators {
            if lowercased.contains(indicator) {
                foundStrong.append(indicator)
            }
        }

        for indicator in mediumIndicators {
            if lowercased.contains(indicator) {
                foundMedium.append(indicator)
            }
        }

        // Determine result
        if !foundStrong.isEmpty {
            return (true, "high", "Found: \(foundStrong.joined(separator: ", "))")
        } else if !foundMedium.isEmpty {
            return (true, "medium", "Found: \(foundMedium.joined(separator: ", "))")
        } else {
            return (false, "high", "No invoice keywords found")
        }
    }

    /// Extract invoice date from OCR text
    public func extractDate(from text: String) -> Date? {
        // Common date patterns
        let patterns = [
            // ISO format: 2024-12-22
            "\\b(\\d{4})-(\\d{2})-(\\d{2})\\b",
            // European format: 22.12.2024 or 22/12/2024
            "\\b(\\d{2})[./](\\d{2})[./](\\d{4})\\b",
            // Colon-separated (OCR artifact): 22:12:2024
            "\\b(\\d{2}):(\\d{2}):(\\d{4})\\b",
            // US format: 12/22/2024
            "\\b(\\d{2})/(\\d{2})/(\\d{4})\\b"
        ]

        // Try to find date near common keywords first (more reliable)
        let dateKeywords = [
            "rechnungsdatum:", "invoice date:", "datum:", "date:",
            "rechnungsdatum", "invoice date", "facture du:", "fecha:"
        ]

        for keyword in dateKeywords {
            if let range = text.range(of: keyword, options: .caseInsensitive) {
                let afterKeyword = String(text[range.upperBound...])
                let nearbyText = String(afterKeyword.prefix(40))

                for pattern in patterns {
                    if let date = extractDateWithPattern(nearbyText, pattern: pattern) {
                        return date
                    }
                }

                // Also try German month format near keywords
                if let date = extractGermanMonthDate(from: nearbyText) {
                    return date
                }
            }
        }

        // Try German month format anywhere in text FIRST
        // This is preferred over numeric dates because billing period dates like "September 2022"
        // are more likely to be the invoice date than other dates like payment due dates
        if let date = extractGermanMonthDate(from: text) {
            return date
        }

        // Fallback: try any numeric date pattern in the text
        for pattern in patterns {
            if let date = extractDateWithPattern(text, pattern: pattern) {
                return date
            }
        }

        return nil
    }

    /// Extract date from German month format like "September 2022"
    private func extractGermanMonthDate(from text: String) -> Date? {
        let germanMonths = [
            "januar", "februar", "märz", "maerz", "april", "mai", "juni",
            "juli", "august", "september", "oktober", "november", "dezember",
            "jan", "feb", "mrz", "apr", "jun", "jul", "aug", "sep", "sept", "okt", "nov", "dez"
        ]

        let lowercased = text.lowercased()
        for month in germanMonths {
            // Use word boundary regex to avoid false positives (e.g., "mai" in "email")
            let monthPattern = "\\b\(NSRegularExpression.escapedPattern(for: month))\\b"
            guard let monthRegex = try? NSRegularExpression(pattern: monthPattern, options: .caseInsensitive),
                  let monthMatch = monthRegex.firstMatch(in: lowercased, range: NSRange(lowercased.startIndex..., in: lowercased)),
                  let monthRange = Range(monthMatch.range, in: lowercased) else {
                continue
            }

            // Look for a 4-digit year after the month
            let afterMonthString = String(String(lowercased[monthRange.upperBound...]).prefix(20))
            let yearPattern = "\\b(20\\d{2})\\b"

            guard let yearRegex = try? NSRegularExpression(pattern: yearPattern),
                  let yearMatch = yearRegex.firstMatch(in: afterMonthString, range: NSRange(afterMonthString.startIndex..., in: afterMonthString)),
                  let yearRange = Range(yearMatch.range, in: afterMonthString) else {
                continue
            }

            let yearString = afterMonthString[yearRange]
            let monthYearString = "\(month) \(yearString)"
            if let date = DateUtils.parseDate(monthYearString) {
                return date
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
        return DateUtils.parseDate(dateString)
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
        return StringUtils.sanitizeCompanyName(name)
    }

    /// Extract all invoice data from OCR text using Text-LLM (legacy method)
    public func extractInvoiceData(from text: String) async throws -> (isInvoice: Bool, date: Date?, company: String?) {
        if config.verbose {
            print("OCR extracted text (\(text.count) characters)")
            print("Sending to Text-LLM for analysis...")
        }

        // Use Text-LLM to analyze the OCR text
        let (isInvoice, date, company) = try await textLLM.analyzeInvoiceText(text)

        if config.verbose {
            print("OCR + Text-LLM Results:")
            print("  Is Invoice: \(isInvoice)")
            print("  Date: \(date?.description ?? "nil")")
            print("  Company: \(company ?? "nil")")
        }

        return (isInvoice, date, company)
    }

    /// Extract only date and company from OCR text (no invoice detection)
    /// Used in Phase 2 after categorization confirms it's an invoice
    public func extractDateAndCompany(from text: String) async throws -> (date: Date?, company: String?) {
        if config.verbose {
            print("Extracting date and company from OCR text (\(text.count) characters)...")
        }

        // Use Text-LLM to extract date and company
        let (date, company) = try await textLLM.extractDateAndCompany(from: text)

        if config.verbose {
            print("Extraction Results:")
            print("  Date: \(date?.description ?? "not found")")
            print("  Company: \(company ?? "not found")")
        }

        return (date, company)
    }
}
