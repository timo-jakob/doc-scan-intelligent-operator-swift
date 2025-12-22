import Foundation
import PDFKit
import AppKit

/// Utilities for PDF processing and conversion
public struct PDFUtils {
    /// Validate that a file is a valid PDF
    public static func validatePDF(at path: String) throws {
        let url = URL(fileURLWithPath: path)

        guard FileManager.default.fileExists(atPath: path) else {
            throw DocScanError.fileNotFound(path)
        }

        guard let document = PDFDocument(url: url) else {
            throw DocScanError.invalidPDF("Unable to open PDF document")
        }

        guard document.pageCount > 0 else {
            throw DocScanError.invalidPDF("PDF has no pages")
        }
    }

    /// Convert the first page of a PDF to an NSImage at specified DPI
    public static func pdfToImage(at path: String, dpi: Int = 150) throws -> NSImage {
        let url = URL(fileURLWithPath: path)

        guard let document = PDFDocument(url: url) else {
            throw DocScanError.pdfConversionFailed("Unable to open PDF document")
        }

        guard let page = document.page(at: 0) else {
            throw DocScanError.pdfConversionFailed("Unable to get first page")
        }

        // Calculate size based on DPI
        let pageRect = page.bounds(for: .mediaBox)
        let scale = CGFloat(dpi) / 72.0  // 72 DPI is the default
        let scaledSize = CGSize(
            width: pageRect.width * scale,
            height: pageRect.height * scale
        )

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
            bitsPerPixel: 0
        ) else {
            throw DocScanError.pdfConversionFailed("Unable to create bitmap representation")
        }

        // Draw PDF page into bitmap
        NSGraphicsContext.saveGraphicsState()
        guard let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
            throw DocScanError.pdfConversionFailed("Unable to create graphics context")
        }

        NSGraphicsContext.current = context
        let cgContext = context.cgContext
        cgContext.setFillColor(NSColor.white.cgColor)
        cgContext.fill(CGRect(origin: .zero, size: scaledSize))
        cgContext.scaleBy(x: scale, y: scale)
        page.draw(with: .mediaBox, to: cgContext)
        NSGraphicsContext.restoreGraphicsState()

        // Create NSImage from bitmap
        let image = NSImage(size: scaledSize)
        image.addRepresentation(bitmap)

        return image
    }

    /// Convert NSImage to PNG data for MLX Vision models
    public static func imageToData(_ image: NSImage) throws -> Data {
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else {
            throw DocScanError.pdfConversionFailed("Unable to convert image to PNG data")
        }
        return pngData
    }

    /// Save NSImage to file (useful for debugging)
    public static func saveImage(_ image: NSImage, to path: String) throws {
        let data = try imageToData(image)
        let url = URL(fileURLWithPath: path)
        try data.write(to: url)
    }
}
