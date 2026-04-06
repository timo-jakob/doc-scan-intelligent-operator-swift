import AppKit
import Foundation
import PDFKit

/// Utilities for PDF processing and conversion
public enum PDFUtils {
    /// Minimum character count to consider direct PDF text extraction successful
    /// Below this threshold, we fall back to OCR (likely a scanned document)
    public static let minimumTextLength = 50

    /// Extract text directly from a PDF without OCR
    /// This is much faster and more accurate for searchable PDFs
    /// Returns nil if the PDF has no embedded text (e.g., scanned documents)
    public static func extractText(from path: String, verbose: Bool = false) -> String? {
        let url = URL(fileURLWithPath: path)
        guard let document = PDFDocument(url: url) else {
            if verbose { print("PDF: Could not open document") }
            return nil
        }
        return extractText(from: document, verbose: verbose)
    }

    /// Check if a PDF has sufficient embedded text for direct extraction
    /// Returns true if direct text extraction should be used instead of OCR
    public static func hasExtractableText(at path: String, verbose: Bool = false) -> Bool {
        guard let text = extractText(from: path, verbose: verbose) else {
            return false
        }
        let hasSufficientText = text.count >= minimumTextLength
        if verbose {
            if hasSufficientText {
                print("PDF: Has extractable text (\(text.count) chars >= \(minimumTextLength) minimum)")
            } else {
                print("PDF: Insufficient text (\(text.count) chars < \(minimumTextLength) minimum), will use OCR")
            }
        }
        return hasSufficientText
    }

    /// Open and validate a PDF file, returning the in-memory document.
    /// Use this to open the PDF once and pass it to other methods.
    public static func openPDF(at path: String) throws(DocScanError) -> PDFDocument {
        guard FileManager.default.fileExists(atPath: path) else {
            throw DocScanError.fileNotFound(path)
        }
        let url = URL(fileURLWithPath: path)
        guard let document = PDFDocument(url: url) else {
            throw DocScanError.invalidPDF("Unable to open PDF document")
        }
        guard document.pageCount > 0 else {
            throw DocScanError.invalidPDF("PDF has no pages")
        }
        return document
    }

    /// Validate that a file is a valid PDF
    public static func validatePDF(at path: String) throws(DocScanError) {
        _ = try openPDF(at: path)
    }

    /// Extract text directly from a pre-opened PDFDocument
    public static func extractText(from document: PDFDocument, verbose: Bool = false) -> String? {
        guard let page = document.page(at: 0) else {
            if verbose { print("PDF: Could not get first page") }
            return nil
        }
        guard let text = page.string, !text.isEmpty else {
            if verbose { print("PDF: No embedded text found (scanned document?)") }
            return nil
        }
        if verbose { print("PDF: Extracted \(text.count) characters directly from PDF") }
        return text
    }

    /// Convert the first page of a pre-opened PDFDocument to an NSImage at specified DPI
    public static func pdfToImage(
        from document: PDFDocument, dpi: Int = 150, verbose: Bool = false,
    ) throws(DocScanError) -> NSImage {
        guard let page = document.page(at: 0) else {
            throw DocScanError.pdfConversionFailed("Unable to get first page")
        }

        // Calculate size based on DPI
        let pageRect = page.bounds(for: .mediaBox)
        let scale = CGFloat(dpi) / 72.0 // 72 DPI is the default
        let scaledSize = CGSize(
            width: pageRect.width * scale,
            height: pageRect.height * scale,
        )

        if verbose {
            print("PDF page size: \(Int(pageRect.width))x\(Int(pageRect.height)) points")
            print("Image size at \(dpi) DPI: \(Int(scaledSize.width))x\(Int(scaledSize.height)) pixels")
        }

        // Create bitmap representation
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(scaledSize.width),
            pixelsHigh: Int(scaledSize.height),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0,
        ) else {
            throw DocScanError.pdfConversionFailed("Unable to create bitmap representation")
        }

        // Draw PDF page into bitmap
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }

        guard let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
            throw DocScanError.pdfConversionFailed("Unable to create graphics context")
        }

        NSGraphicsContext.current = context
        let cgContext = context.cgContext
        cgContext.setFillColor(NSColor.white.cgColor)
        cgContext.fill(CGRect(origin: .zero, size: scaledSize))
        cgContext.scaleBy(x: scale, y: scale)
        page.draw(with: .mediaBox, to: cgContext)

        // Create NSImage from bitmap
        let image = NSImage(size: scaledSize)
        image.addRepresentation(bitmap)

        return image
    }

    /// Convenience: convert first page of a PDF file to NSImage (opens the file).
    /// Prefer `pdfToImage(from:dpi:verbose:)` when you already have an open `PDFDocument`.
    public static func pdfToImage(
        at path: String, dpi: Int = 150, verbose: Bool = false,
    ) throws(DocScanError) -> NSImage {
        let document = try openPDF(at: path)
        return try pdfToImage(from: document, dpi: dpi, verbose: verbose)
    }

    /// Convert NSImage to PNG data for MLX Vision models
    public static func imageToData(_ image: NSImage) throws(DocScanError) -> Data {
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:])
        else {
            throw DocScanError.pdfConversionFailed("Unable to convert image to PNG data")
        }
        return pngData
    }

    /// Save NSImage to file (useful for debugging)
    public static func saveImage(_ image: NSImage, to path: String) throws(DocScanError) {
        let data = try imageToData(image)
        let url = URL(fileURLWithPath: path)
        do {
            try data.write(to: url)
        } catch {
            throw DocScanError.fileOperationFailed("Failed to save image: \(error.localizedDescription)")
        }
    }
}
