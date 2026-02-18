import AppKit
import Foundation
import Vision

/// OCR engine using Apple's Vision framework for text recognition + Text-LLM for analysis
public class OCREngine {
    private let config: Configuration
    private let textLLM: TextLLMManager

    public init(config: Configuration) {
        self.config = config
        textLLM = TextLLMManager(config: config)
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
        try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    continuation.resume(throwing: DocScanError.extractionFailed("OCR failed: \(error.localizedDescription)"))
                    return
                }

                guard let observations = request.results as? [VNRecognizedTextObservation] else {
                    continuation.resume(throwing: DocScanError.extractionFailed("No text observations found"))
                    return
                }

                let recognizedText = Self.extractTextFromObservations(observations)

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
        let tileHeight = 800 // Tile height in pixels
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

    /// Extract text strings from Vision observations
    /// Extracted to avoid nested closure complexity
    /// Internal access for testability
    static func extractTextFromObservations(_ observations: [VNRecognizedTextObservation]) -> String {
        observations.compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
    }

    /// Detect if text contains invoice indicators (simple boolean)
    public func detectInvoice(from text: String) -> Bool {
        let (isInvoice, _, _) = Self.detectInvoiceKeywords(from: text)
        return isInvoice
    }

    /// Detect invoice keywords with confidence and reason (instance method)
    public func detectInvoiceKeywords(from text: String) -> (isInvoice: Bool, confidence: String, reason: String?) {
        Self.detectInvoiceKeywords(from: text)
    }

    /// Detect invoice keywords with confidence and reason (static, shared implementation)
    /// Legacy method - delegates to generic detectKeywords
    public static func detectInvoiceKeywords(from text: String) -> (isInvoice: Bool, confidence: String, reason: String?) {
        let result = detectKeywords(for: .invoice, from: text)
        return (result.isMatch, result.confidence, result.reason)
    }

    /// Generic keyword detection for any document type
    /// Returns whether the text matches the document type, confidence level, and reason
    public static func detectKeywords(
        for documentType: DocumentType,
        from text: String
    ) -> (isMatch: Bool, confidence: String, reason: String?) {
        let lowercased = text.lowercased()

        let strongIndicators = documentType.strongKeywords
        let mediumIndicators = documentType.mediumKeywords

        var foundStrong: [String] = []
        var foundMedium: [String] = []

        for indicator in strongIndicators where lowercased.contains(indicator) {
            foundStrong.append(indicator)
        }

        for indicator in mediumIndicators where lowercased.contains(indicator) {
            foundMedium.append(indicator)
        }

        // Determine result
        if !foundStrong.isEmpty {
            return (true, "high", "Found: \(foundStrong.joined(separator: ", "))")
        } else if !foundMedium.isEmpty {
            return (true, "medium", "Found: \(foundMedium.joined(separator: ", "))")
        } else {
            return (false, "high", "No \(documentType.displayName.lowercased()) keywords found")
        }
    }

    /// Instance method for generic keyword detection
    public func detectKeywords(for documentType: DocumentType, from text: String) -> (isMatch: Bool, confidence: String, reason: String?) {
        Self.detectKeywords(for: documentType, from: text)
    }

    /// Extract invoice date from OCR text
    /// Uses shared DateUtils for consistent date extraction across the codebase
    public func extractDate(from text: String) -> Date? {
        DateUtils.extractDateFromText(text)
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
            "sarl", "s.a.", "kg", "ohg",
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
        StringUtils.sanitizeCompanyName(name)
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
