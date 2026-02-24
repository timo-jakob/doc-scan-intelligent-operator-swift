import AppKit
import Foundation
import Vision

/// Result of keyword-based document type detection
public struct KeywordResult: Equatable, Sendable {
    public let isMatch: Bool
    public let confidence: ConfidenceLevel
    public let reason: String?

    public init(isMatch: Bool, confidence: ConfidenceLevel, reason: String?) {
        self.isMatch = isMatch
        self.confidence = confidence
        self.reason = reason
    }
}

/// OCR engine using Apple's Vision framework for text recognition
public struct OCREngine: Sendable {
    private let config: Configuration

    public init(config: Configuration) {
        self.config = config
    }

    /// Extract text from an image using Vision OCR.
    /// Runs blocking Vision operations on a background queue to avoid
    /// blocking the cooperative thread pool.
    /// For very tall images (aspect ratio > 4:1), tiles the image to ensure full text extraction.
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
                let ratio = String(format: "%.1f", aspectRatio)
                print("OCR: Tall image detected (aspect ratio \(ratio):1), using tiled OCR")
            }
            return try await runOnBackgroundQueue { try extractTextTiled(from: cgImage) }
        }

        return try await runOnBackgroundQueue { try extractTextSingle(from: cgImage) }
    }

    /// Run a blocking operation on a background queue to avoid blocking the cooperative thread pool.
    private func runOnBackgroundQueue<T: Sendable>(_ work: @Sendable @escaping () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let result = try work()
                    continuation.resume(returning: result)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// Extract text from a single image (standard OCR)
    private func extractTextSingle(from cgImage: CGImage) throws -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["en-US", "de-DE", "fr-FR", "es-ES"]
        request.usesLanguageCorrection = true

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try handler.perform([request])

        guard let observations = request.results else {
            throw DocScanError.extractionFailed("No text observations found")
        }

        let recognizedText = Self.extractTextFromObservations(observations)
        guard !recognizedText.isEmpty else {
            throw DocScanError.extractionFailed("No text recognized")
        }
        return recognizedText
    }

    /// Extract text from a tall image by splitting into tiles
    private func extractTextTiled(from cgImage: CGImage) throws -> String {
        let width = cgImage.width
        let height = cgImage.height
        let tileHeight = 800 // Tile height in pixels
        var tileTexts: [String] = []

        for tileY in stride(from: 0, to: height, by: tileHeight) {
            let cropHeight = min(tileHeight, height - tileY)
            let cropRect = CGRect(x: 0, y: tileY, width: width, height: cropHeight)

            guard let croppedImage = cgImage.cropping(to: cropRect) else {
                continue
            }

            do {
                let tileText = try extractTextSingle(from: croppedImage)
                tileTexts.append(tileText)
            } catch {
                // Continue with other tiles even if one fails
                if config.verbose {
                    print("OCR: Tile at y=\(tileY) failed: \(error.localizedDescription)")
                }
            }
        }

        guard !tileTexts.isEmpty else {
            throw DocScanError.extractionFailed("No text recognized from any tile")
        }

        return tileTexts.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Extract text strings from Vision observations
    /// Extracted to avoid nested closure complexity
    /// Internal access for testability
    static func extractTextFromObservations(_ observations: [VNRecognizedTextObservation]) -> String {
        observations.compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
    }

    /// Generic keyword detection for any document type
    /// Returns whether the text matches the document type, confidence level, and reason
    public static func detectKeywords(
        for documentType: DocumentType,
        from text: String
    ) -> KeywordResult {
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
            let reason = "Found: \(foundStrong.joined(separator: ", "))"
            return KeywordResult(isMatch: true, confidence: .high, reason: reason)
        } else if !foundMedium.isEmpty {
            let reason = "Found: \(foundMedium.joined(separator: ", "))"
            return KeywordResult(isMatch: true, confidence: .medium, reason: reason)
        } else {
            let typeName = documentType.displayName.lowercased()
            return KeywordResult(
                isMatch: false,
                confidence: .high,
                reason: "No \(typeName) keywords found"
            )
        }
    }

    /// Instance method for generic keyword detection
    public func detectKeywords(
        for documentType: DocumentType,
        from text: String
    ) -> KeywordResult {
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
}
