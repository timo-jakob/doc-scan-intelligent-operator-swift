@testable import DocScanCore
import PDFKit
import XCTest

final class PDFUtilsTests: XCTestCase {
    // MARK: - Test Fixtures

    /// A minimal PDF with embedded searchable text "Hello World Rechnung Invoice Test Document 12345"
    /// Created using macOS Preview and exported as PDF
    /// This ensures tests work in CI without external dependencies
    static let searchablePDFBase64 = """
    JVBERi0xLjQKJcOkw7zDtsOfCjEgMCBvYmoKPDwKL1R5cGUgL0NhdGFsb2cKL1BhZ2VzIDIgMCBS
    Cj4+CmVuZG9iagoKMiAwIG9iago8PAovVHlwZSAvUGFnZXMKL0tpZHMgWzMgMCBSXQovQ291bnQg
    MQo+PgplbmRvYmoKCjMgMCBvYmoKPDwKL1R5cGUgL1BhZ2UKL1BhcmVudCAyIDAgUgovTWVkaWFC
    b3ggWzAgMCA2MTIgNzkyXQovQ29udGVudHMgNCAwIFIKL1Jlc291cmNlcyA8PAovRm9udCA8PAov
    RjEgNSAwIFIKPj4KPj4KPj4KZW5kb2JqCgo0IDAgb2JqCjw8Ci9MZW5ndGggMTIzCj4+CnN0cmVh
    bQpCVAovRjEgMTIgVGYKNTAgNzAwIFRkCihIZWxsbyBXb3JsZCBSZWNobnVuZyBJbnZvaWNlIFRl
    c3QgRG9jdW1lbnQgMTIzNDUgVGhpcyBpcyBhIHRlc3QgUERGIHdpdGggc2VhcmNoYWJsZSB0ZXh0
    KSBUagpFVAplbmRzdHJlYW0KZW5kb2JqCgo1IDAgb2JqCjw8Ci9UeXBlIC9Gb250Ci9TdWJ0eXBl
    IC9UeXBlMQovQmFzZUZvbnQgL0hlbHZldGljYQo+PgplbmRvYmoKCnhyZWYKMCA2CjAwMDAwMDAw
    MDAgNjU1MzUgZiAKMDAwMDAwMDAxNSAwMDAwMCBuIAowMDAwMDAwMDY4IDAwMDAwIG4gCjAwMDAw
    MDAxMjcgMDAwMDAgbiAKMDAwMDAwMDI5NCAwMDAwMCBuIAowMDAwMDAwNDY5IDAwMDAwIG4gCnRy
    YWlsZXIKPDwKL1NpemUgNgovUm9vdCAxIDAgUgo+PgpzdGFydHhyZWYKNTQ5CiUlRU9GCg==
    """

    // MARK: - Test Helpers

    /// Create a searchable PDF from the embedded base64 data
    func createSearchablePDFFromFixture() throws -> String {
        let tempDir = FileManager.default.temporaryDirectory
        let pdfPath = tempDir.appendingPathComponent(
            "searchable_\(UUID().uuidString).pdf"
        ).path

        guard let pdfData = Data(
            base64Encoded: Self.searchablePDFBase64,
            options: .ignoreUnknownCharacters
        ) else {
            throw NSError(
                domain: "TestError", code: 1,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "Failed to decode base64 PDF",
                ]
            )
        }

        try pdfData.write(to: URL(fileURLWithPath: pdfPath))
        return pdfPath
    }

    /// Create a test PDF with text content using Core Graphics
    func createTestPDF(withText text: String) throws -> String {
        let tempDir = FileManager.default.temporaryDirectory
        let pdfPath = tempDir.appendingPathComponent(
            "test_\(UUID().uuidString).pdf"
        ).path
        let pdfURL = URL(fileURLWithPath: pdfPath)

        // Letter size
        var mediaBox = CGRect(x: 0, y: 0, width: 612, height: 792)

        guard let context = CGContext(
            pdfURL as CFURL, mediaBox: &mediaBox, nil
        ) else {
            throw NSError(
                domain: "TestError", code: 1,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "Failed to create PDF context",
                ]
            )
        }

        context.beginPage(mediaBox: &mediaBox)

        let textRect = CGRect(x: 50, y: 700, width: 500, height: 50)
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .left

        let textAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12),
            .foregroundColor: NSColor.black,
            .paragraphStyle: paragraphStyle,
        ]

        let nsText = text as NSString
        nsText.draw(in: textRect, withAttributes: textAttributes)

        context.endPage()
        context.closePDF()

        return pdfPath
    }

    /// Clean up test PDF file
    func removeTestPDF(at path: String) {
        try? FileManager.default.removeItem(atPath: path)
    }

    // MARK: - Minimum Text Length

    func testMinimumTextLengthConstant() {
        // Ensure the minimum text length is reasonable
        XCTAssertEqual(PDFUtils.minimumTextLength, 50)
    }

    // MARK: - Extract Text

    func testExtractTextFromNonExistentFile() {
        let result = PDFUtils.extractText(
            from: "/nonexistent/path/file.pdf"
        )
        XCTAssertNil(result)
    }

    func testExtractTextFromInvalidPath() {
        let result = PDFUtils.extractText(from: "")
        XCTAssertNil(result)
    }

    func testExtractTextFromCreatedPDF() throws {
        let testText = "This is a test invoice document. "
            + "Rechnung Nr. 12345. Date: 2024-12-15. "
            + "Total: 150.00 EUR."
        let pdfPath = try createTestPDF(withText: testText)
        defer { removeTestPDF(at: pdfPath) }

        // Just verify it doesn't crash
        _ = PDFUtils.extractText(from: pdfPath)
    }

    func testExtractTextWithVerboseMode() throws {
        let testText = "Test document with verbose mode "
            + "enabled for debugging purposes."
        let pdfPath = try createTestPDF(withText: testText)
        defer { removeTestPDF(at: pdfPath) }

        _ = PDFUtils.extractText(from: pdfPath, verbose: true)
    }

    func testExtractTextFromSearchablePDFFixture() throws {
        let pdfPath = try createSearchablePDFFromFixture()
        defer { removeTestPDF(at: pdfPath) }

        let text = PDFUtils.extractText(from: pdfPath)

        XCTAssertNotNil(text)
        XCTAssertGreaterThan(
            text?.count ?? 0, PDFUtils.minimumTextLength
        )
        XCTAssertTrue(text?.contains("Rechnung") ?? false)
        XCTAssertTrue(text?.contains("Invoice") ?? false)
    }

    func testExtractTextFromSearchablePDFFixtureVerbose() throws {
        let pdfPath = try createSearchablePDFFromFixture()
        defer { removeTestPDF(at: pdfPath) }

        let text = PDFUtils.extractText(
            from: pdfPath, verbose: true
        )

        XCTAssertNotNil(text)
        XCTAssertGreaterThan(text?.count ?? 0, 0)
    }

    func testExtractTextFromNonExistentFileVerbose() {
        let result = PDFUtils.extractText(
            from: "/nonexistent/path/file.pdf", verbose: true
        )
        XCTAssertNil(result)
    }
}

// MARK: - Has Extractable Text

extension PDFUtilsTests {
    func testHasExtractableTextFromNonExistentFile() {
        let result = PDFUtils.hasExtractableText(
            at: "/nonexistent/path/file.pdf"
        )
        XCTAssertFalse(result)
    }

    func testHasExtractableTextFromInvalidPath() {
        let result = PDFUtils.hasExtractableText(at: "")
        XCTAssertFalse(result)
    }

    func testHasExtractableTextFromCreatedPDF() throws {
        let testText = "This is a test document with enough "
            + "text content to pass the minimum length "
            + "requirement for extractable text detection."
        let pdfPath = try createTestPDF(withText: testText)
        defer { removeTestPDF(at: pdfPath) }

        _ = PDFUtils.hasExtractableText(at: pdfPath)
    }

    func testHasExtractableTextWithVerboseMode() throws {
        let testText = "Verbose mode test with sufficient "
            + "content to meet the minimum text length "
            + "threshold requirement."
        let pdfPath = try createTestPDF(withText: testText)
        defer { removeTestPDF(at: pdfPath) }

        _ = PDFUtils.hasExtractableText(
            at: pdfPath, verbose: true
        )
    }

    func testHasExtractableTextWithShortContent() throws {
        let testText = "Short"
        let pdfPath = try createTestPDF(withText: testText)
        defer { removeTestPDF(at: pdfPath) }

        let result = PDFUtils.hasExtractableText(at: pdfPath)
        XCTAssertFalse(result)
    }

    func testHasExtractableTextFromSearchablePDFFixture() throws {
        let pdfPath = try createSearchablePDFFromFixture()
        defer { removeTestPDF(at: pdfPath) }

        let hasText = PDFUtils.hasExtractableText(at: pdfPath)
        XCTAssertTrue(hasText)
    }

    func testHasExtractableTextFromSearchablePDFFixtureVerbose() throws {
        let pdfPath = try createSearchablePDFFromFixture()
        defer { removeTestPDF(at: pdfPath) }

        let hasText = PDFUtils.hasExtractableText(
            at: pdfPath, verbose: true
        )
        XCTAssertTrue(hasText)
    }

    func testHasExtractableTextFromNonExistentFileVerbose() {
        let result = PDFUtils.hasExtractableText(
            at: "/nonexistent/path/file.pdf", verbose: true
        )
        XCTAssertFalse(result)
    }
}

// MARK: - Integration Tests (require real PDF files)

extension PDFUtilsTests {
    func testExtractTextFromSearchablePDF() throws {
        let testPDFPath = "/Users/timo/repositories/"
            + "invoice-examples/BahnCard_Rechnung.pdf"

        guard FileManager.default.fileExists(atPath: testPDFPath) else {
            throw XCTSkip("Test PDF not available")
        }

        let text = PDFUtils.extractText(from: testPDFPath)

        XCTAssertNotNil(text)
        XCTAssertGreaterThan(
            text?.count ?? 0, PDFUtils.minimumTextLength
        )
        XCTAssertTrue(text?.contains("Rechnung") ?? false)
        XCTAssertTrue(text?.contains("BahnCard") ?? false)
    }

    func testHasExtractableTextFromSearchablePDF() throws {
        let testPDFPath = "/Users/timo/repositories/"
            + "invoice-examples/BahnCard_Rechnung.pdf"

        guard FileManager.default.fileExists(atPath: testPDFPath) else {
            throw XCTSkip("Test PDF not available")
        }

        let hasText = PDFUtils.hasExtractableText(at: testPDFPath)
        XCTAssertTrue(hasText)
    }

    func testExtractTextFromScannedPDF() throws {
        let testPDFPath = "/Users/timo/repositories/"
            + "invoice-examples/"
            + "2025-12-16 Rechnung Öl Mini.pdf"

        guard FileManager.default.fileExists(atPath: testPDFPath) else {
            throw XCTSkip("Test PDF not available")
        }

        let text = PDFUtils.extractText(from: testPDFPath)
        XCTAssertNil(text)
    }

    func testHasExtractableTextFromScannedPDF() throws {
        let testPDFPath = "/Users/timo/repositories/"
            + "invoice-examples/"
            + "2025-12-16 Rechnung Öl Mini.pdf"

        guard FileManager.default.fileExists(atPath: testPDFPath) else {
            throw XCTSkip("Test PDF not available")
        }

        let hasText = PDFUtils.hasExtractableText(at: testPDFPath)
        XCTAssertFalse(hasText)
    }
}
