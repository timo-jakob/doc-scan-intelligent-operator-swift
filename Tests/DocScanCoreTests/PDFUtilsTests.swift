import XCTest
@testable import DocScanCore

final class PDFUtilsTests: XCTestCase {

    // MARK: - Minimum Text Length

    func testMinimumTextLengthConstant() {
        // Ensure the minimum text length is reasonable
        XCTAssertEqual(PDFUtils.minimumTextLength, 50)
    }

    // MARK: - Extract Text

    func testExtractTextFromNonExistentFile() {
        let result = PDFUtils.extractText(from: "/nonexistent/path/file.pdf")
        XCTAssertNil(result)
    }

    func testExtractTextFromInvalidPath() {
        let result = PDFUtils.extractText(from: "")
        XCTAssertNil(result)
    }

    // MARK: - Has Extractable Text

    func testHasExtractableTextFromNonExistentFile() {
        let result = PDFUtils.hasExtractableText(at: "/nonexistent/path/file.pdf")
        XCTAssertFalse(result)
    }

    func testHasExtractableTextFromInvalidPath() {
        let result = PDFUtils.hasExtractableText(at: "")
        XCTAssertFalse(result)
    }

    // MARK: - Integration Tests (require real PDF files)

    /// Test with a searchable PDF if available in test resources
    func testExtractTextFromSearchablePDF() throws {
        // This test would require a test PDF file
        // Skip if no test files are available
        let testPDFPath = "/Users/timo/repositories/invoice-examples/BahnCard_Rechnung.pdf"

        guard FileManager.default.fileExists(atPath: testPDFPath) else {
            throw XCTSkip("Test PDF not available")
        }

        let text = PDFUtils.extractText(from: testPDFPath)

        XCTAssertNotNil(text)
        XCTAssertGreaterThan(text?.count ?? 0, PDFUtils.minimumTextLength)

        // Verify key content is present
        XCTAssertTrue(text?.contains("Rechnung") ?? false)
        XCTAssertTrue(text?.contains("BahnCard") ?? false)
    }

    func testHasExtractableTextFromSearchablePDF() throws {
        let testPDFPath = "/Users/timo/repositories/invoice-examples/BahnCard_Rechnung.pdf"

        guard FileManager.default.fileExists(atPath: testPDFPath) else {
            throw XCTSkip("Test PDF not available")
        }

        let hasText = PDFUtils.hasExtractableText(at: testPDFPath)
        XCTAssertTrue(hasText)
    }

    func testExtractTextFromScannedPDF() throws {
        // Scanned PDFs should return nil (no embedded text)
        let testPDFPath = "/Users/timo/repositories/invoice-examples/2025-12-16 Rechnung Öl Mini.pdf"

        guard FileManager.default.fileExists(atPath: testPDFPath) else {
            throw XCTSkip("Test PDF not available")
        }

        let text = PDFUtils.extractText(from: testPDFPath)

        // Scanned PDF should have no extractable text
        XCTAssertNil(text)
    }

    func testHasExtractableTextFromScannedPDF() throws {
        let testPDFPath = "/Users/timo/repositories/invoice-examples/2025-12-16 Rechnung Öl Mini.pdf"

        guard FileManager.default.fileExists(atPath: testPDFPath) else {
            throw XCTSkip("Test PDF not available")
        }

        let hasText = PDFUtils.hasExtractableText(at: testPDFPath)
        XCTAssertFalse(hasText)
    }
}
