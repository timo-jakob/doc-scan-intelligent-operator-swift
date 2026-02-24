import CoreGraphics
@testable import DocScanCore
import Foundation

/// Shared test utilities used across multiple test files.
enum TestHelpers {
    /// Create a minimal single-page PDF at the given URL.
    /// Useful for tests that need a valid PDF file without real content.
    static func createMinimalPDF(at url: URL) throws {
        let pdfData = NSMutableData()
        guard let consumer = CGDataConsumer(data: pdfData as CFMutableData),
              let context = CGContext(consumer: consumer, mediaBox: nil, nil)
        else {
            throw DocScanError.pdfConversionFailed("Could not create PDF context")
        }
        var mediaBox = CGRect(x: 0, y: 0, width: 100, height: 100)
        context.beginPage(mediaBox: &mediaBox)
        context.endPage()
        context.closePDF()
        try (pdfData as Data).write(to: url)
    }
}
