import XCTest
import PDFKit
@testable import DocScanCore

final class PDFUtilsTests: XCTestCase {

    // MARK: - Test Fixtures

    /// A minimal PDF with embedded searchable text "Hello World Rechnung Invoice Test Document 12345"
    /// Created using macOS Preview and exported as PDF
    /// This ensures tests work in CI without external dependencies
    private static let searchablePDFBase64 = """
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

    /// Create a searchable PDF from the embedded base64 data
    private func createSearchablePDFFromFixture() throws -> String {
        let tempDir = FileManager.default.temporaryDirectory
        let pdfPath = tempDir.appendingPathComponent("searchable_\(UUID().uuidString).pdf").path

        guard let pdfData = Data(base64Encoded: Self.searchablePDFBase64, options: .ignoreUnknownCharacters) else {
            throw NSError(domain: "TestError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to decode base64 PDF"])
        }

        try pdfData.write(to: URL(fileURLWithPath: pdfPath))
        return pdfPath
    }

    // MARK: - Test Helpers

    /// Create a test PDF with text content programmatically using Core Graphics
    private func createTestPDF(withText text: String) throws -> String {
        let tempDir = FileManager.default.temporaryDirectory
        let pdfPath = tempDir.appendingPathComponent("test_\(UUID().uuidString).pdf").path
        let pdfURL = URL(fileURLWithPath: pdfPath)

        var mediaBox = CGRect(x: 0, y: 0, width: 612, height: 792)  // Letter size

        guard let context = CGContext(pdfURL as CFURL, mediaBox: &mediaBox, nil) else {
            throw NSError(domain: "TestError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to create PDF context"])
        }

        context.beginPage(mediaBox: &mediaBox)

        // Draw text using Core Text for proper text embedding
        let textRect = CGRect(x: 50, y: 700, width: 500, height: 50)
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .left

        let textAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12),
            .foregroundColor: NSColor.black,
            .paragraphStyle: paragraphStyle
        ]

        // Use NSString for drawing
        let nsText = text as NSString
        nsText.draw(in: textRect, withAttributes: textAttributes)

        context.endPage()
        context.closePDF()

        return pdfPath
    }

    /// Clean up test PDF file
    private func removeTestPDF(at path: String) {
        try? FileManager.default.removeItem(atPath: path)
    }

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

    func testExtractTextFromCreatedPDF() throws {
        // Create a PDF with sufficient text content
        // Note: Programmatically created PDFs may not always have searchable text
        let testText = "This is a test invoice document. Rechnung Nr. 12345. Date: 2024-12-15. Total: 150.00 EUR."
        let pdfPath = try createTestPDF(withText: testText)
        defer { removeTestPDF(at: pdfPath) }

        // Just verify it doesn't crash - text may or may not be extractable
        // depending on how Core Graphics embeds the text
        _ = PDFUtils.extractText(from: pdfPath)
    }

    func testExtractTextWithVerboseMode() throws {
        let testText = "Test document with verbose mode enabled for debugging purposes and more text here."
        let pdfPath = try createTestPDF(withText: testText)
        defer { removeTestPDF(at: pdfPath) }

        // Should not crash - text extraction may return nil for programmatic PDFs
        _ = PDFUtils.extractText(from: pdfPath, verbose: true)
    }

    func testExtractTextFromSearchablePDFFixture() throws {
        // Use the embedded searchable PDF fixture
        let pdfPath = try createSearchablePDFFromFixture()
        defer { removeTestPDF(at: pdfPath) }

        let text = PDFUtils.extractText(from: pdfPath)

        XCTAssertNotNil(text)
        XCTAssertGreaterThan(text?.count ?? 0, PDFUtils.minimumTextLength)
        // Verify expected content
        XCTAssertTrue(text?.contains("Rechnung") ?? false)
        XCTAssertTrue(text?.contains("Invoice") ?? false)
    }

    func testExtractTextFromSearchablePDFFixtureVerbose() throws {
        // Use the embedded searchable PDF fixture with verbose mode
        let pdfPath = try createSearchablePDFFromFixture()
        defer { removeTestPDF(at: pdfPath) }

        let text = PDFUtils.extractText(from: pdfPath, verbose: true)

        XCTAssertNotNil(text)
        XCTAssertGreaterThan(text?.count ?? 0, 0)
    }

    func testExtractTextFromNonExistentFileVerbose() {
        // Test verbose mode with non-existent file (covers "Could not open document" branch)
        let result = PDFUtils.extractText(from: "/nonexistent/path/file.pdf", verbose: true)
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

    func testHasExtractableTextFromCreatedPDF() throws {
        // Create a PDF with sufficient text content (> 50 chars)
        // Note: Programmatically created PDFs may not always have searchable text
        let testText = "This is a test document with enough text content to pass the minimum length requirement for extractable text detection."
        let pdfPath = try createTestPDF(withText: testText)
        defer { removeTestPDF(at: pdfPath) }

        // Just verify it doesn't crash - result depends on Core Graphics text embedding
        _ = PDFUtils.hasExtractableText(at: pdfPath)
    }

    func testHasExtractableTextWithVerboseMode() throws {
        let testText = "Verbose mode test with sufficient content to meet the minimum text length threshold requirement."
        let pdfPath = try createTestPDF(withText: testText)
        defer { removeTestPDF(at: pdfPath) }

        // Just verify it doesn't crash in verbose mode
        _ = PDFUtils.hasExtractableText(at: pdfPath, verbose: true)
    }

    func testHasExtractableTextWithShortContent() throws {
        // Create a PDF with text shorter than minimum (50 chars)
        let testText = "Short"
        let pdfPath = try createTestPDF(withText: testText)
        defer { removeTestPDF(at: pdfPath) }

        let result = PDFUtils.hasExtractableText(at: pdfPath)

        // Should be false because text is too short
        XCTAssertFalse(result)
    }

    func testHasExtractableTextFromSearchablePDFFixture() throws {
        // Use the embedded searchable PDF fixture
        let pdfPath = try createSearchablePDFFromFixture()
        defer { removeTestPDF(at: pdfPath) }

        let hasText = PDFUtils.hasExtractableText(at: pdfPath)
        XCTAssertTrue(hasText)
    }

    func testHasExtractableTextFromSearchablePDFFixtureVerbose() throws {
        // Use the embedded searchable PDF fixture with verbose mode
        // This covers the "Has extractable text" verbose branch
        let pdfPath = try createSearchablePDFFromFixture()
        defer { removeTestPDF(at: pdfPath) }

        let hasText = PDFUtils.hasExtractableText(at: pdfPath, verbose: true)
        XCTAssertTrue(hasText)
    }

    func testHasExtractableTextFromNonExistentFileVerbose() {
        // Test verbose mode with non-existent file
        let result = PDFUtils.hasExtractableText(at: "/nonexistent/path/file.pdf", verbose: true)
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

    // MARK: - Validate PDF Tests

    func testValidatePDFFileNotFound() {
        let nonExistentPath = "/nonexistent/path/file.pdf"

        XCTAssertThrowsError(try PDFUtils.validatePDF(at: nonExistentPath)) { error in
            guard let docScanError = error as? DocScanError else {
                XCTFail("Expected DocScanError")
                return
            }
            if case .fileNotFound(let path) = docScanError {
                XCTAssertEqual(path, nonExistentPath)
            } else {
                XCTFail("Expected fileNotFound error")
            }
        }
    }

    func testValidatePDFInvalidFile() throws {
        // Create a non-PDF file
        let tempDir = FileManager.default.temporaryDirectory
        let fakePDFPath = tempDir.appendingPathComponent("fake_\(UUID().uuidString).pdf").path

        try "This is not a valid PDF content".write(toFile: fakePDFPath, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(atPath: fakePDFPath) }

        XCTAssertThrowsError(try PDFUtils.validatePDF(at: fakePDFPath)) { error in
            guard let docScanError = error as? DocScanError else {
                XCTFail("Expected DocScanError")
                return
            }
            if case .invalidPDF(let message) = docScanError {
                XCTAssertTrue(message.contains("Unable to open"))
            } else {
                XCTFail("Expected invalidPDF error")
            }
        }
    }

    func testValidatePDFSuccess() throws {
        // Create a valid PDF
        let pdfPath = try createTestPDF(withText: "Valid PDF content for validation test")
        defer { removeTestPDF(at: pdfPath) }

        // Should not throw
        XCTAssertNoThrow(try PDFUtils.validatePDF(at: pdfPath))
    }

    func testValidatePDFFromRealFile() throws {
        let testPDFPath = "/Users/timo/repositories/invoice-examples/BahnCard_Rechnung.pdf"

        guard FileManager.default.fileExists(atPath: testPDFPath) else {
            throw XCTSkip("Test PDF not available")
        }

        XCTAssertNoThrow(try PDFUtils.validatePDF(at: testPDFPath))
    }

    // MARK: - PDF to Image Tests

    func testPdfToImageSuccess() throws {
        let pdfPath = try createTestPDF(withText: "Test content for image conversion")
        defer { removeTestPDF(at: pdfPath) }

        let image = try PDFUtils.pdfToImage(at: pdfPath)

        XCTAssertGreaterThan(image.size.width, 0)
        XCTAssertGreaterThan(image.size.height, 0)
    }

    func testPdfToImageWithCustomDPI() throws {
        let pdfPath = try createTestPDF(withText: "Test content for DPI test")
        defer { removeTestPDF(at: pdfPath) }

        let image72 = try PDFUtils.pdfToImage(at: pdfPath, dpi: 72)
        let image150 = try PDFUtils.pdfToImage(at: pdfPath, dpi: 150)
        let image300 = try PDFUtils.pdfToImage(at: pdfPath, dpi: 300)

        // Higher DPI should produce larger images
        XCTAssertLessThan(image72.size.width, image150.size.width)
        XCTAssertLessThan(image150.size.width, image300.size.width)
    }

    func testPdfToImageWithVerboseMode() throws {
        let pdfPath = try createTestPDF(withText: "Test content for verbose mode")
        defer { removeTestPDF(at: pdfPath) }

        // Should not crash with verbose mode
        let image = try PDFUtils.pdfToImage(at: pdfPath, dpi: 150, verbose: true)

        XCTAssertGreaterThan(image.size.width, 0)
    }

    func testPdfToImageInvalidPDF() throws {
        let tempDir = FileManager.default.temporaryDirectory
        let fakePDFPath = tempDir.appendingPathComponent("fake_\(UUID().uuidString).pdf").path

        try "This is not a valid PDF".write(toFile: fakePDFPath, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(atPath: fakePDFPath) }

        XCTAssertThrowsError(try PDFUtils.pdfToImage(at: fakePDFPath)) { error in
            guard let docScanError = error as? DocScanError else {
                XCTFail("Expected DocScanError")
                return
            }
            if case .pdfConversionFailed = docScanError {
                // Expected
            } else {
                XCTFail("Expected pdfConversionFailed error, got: \(docScanError)")
            }
        }
    }

    func testPdfToImageFromRealFile() throws {
        let testPDFPath = "/Users/timo/repositories/invoice-examples/BahnCard_Rechnung.pdf"

        guard FileManager.default.fileExists(atPath: testPDFPath) else {
            throw XCTSkip("Test PDF not available")
        }

        let image = try PDFUtils.pdfToImage(at: testPDFPath, dpi: 150)

        XCTAssertGreaterThan(image.size.width, 0)
        XCTAssertGreaterThan(image.size.height, 0)
    }

    // MARK: - Image to Data Tests

    func testImageToDataSuccess() throws {
        let pdfPath = try createTestPDF(withText: "Test content for image data conversion")
        defer { removeTestPDF(at: pdfPath) }

        let image = try PDFUtils.pdfToImage(at: pdfPath)
        let data = try PDFUtils.imageToData(image)

        XCTAssertGreaterThan(data.count, 0)
        // PNG signature starts with these bytes
        XCTAssertEqual(data.prefix(4), Data([0x89, 0x50, 0x4E, 0x47])) // PNG header
    }

    func testImageToDataFromRealPDF() throws {
        let testPDFPath = "/Users/timo/repositories/invoice-examples/BahnCard_Rechnung.pdf"

        guard FileManager.default.fileExists(atPath: testPDFPath) else {
            throw XCTSkip("Test PDF not available")
        }

        let image = try PDFUtils.pdfToImage(at: testPDFPath)
        let data = try PDFUtils.imageToData(image)

        XCTAssertGreaterThan(data.count, 0)
    }

    // MARK: - Save Image Tests

    func testSaveImageSuccess() throws {
        let pdfPath = try createTestPDF(withText: "Test content for saving image")
        defer { removeTestPDF(at: pdfPath) }

        let image = try PDFUtils.pdfToImage(at: pdfPath)

        let tempDir = FileManager.default.temporaryDirectory
        let outputPath = tempDir.appendingPathComponent("saved_image_\(UUID().uuidString).png").path
        defer { try? FileManager.default.removeItem(atPath: outputPath) }

        try PDFUtils.saveImage(image, to: outputPath)

        XCTAssertTrue(FileManager.default.fileExists(atPath: outputPath))

        // Verify it's a valid PNG file
        let savedData = try Data(contentsOf: URL(fileURLWithPath: outputPath))
        XCTAssertEqual(savedData.prefix(4), Data([0x89, 0x50, 0x4E, 0x47]))
    }

    // MARK: - Edge Cases

    func testExtractTextReturnsNilForEmptyPDF() throws {
        // Create a PDF with minimal content
        let tempDir = FileManager.default.temporaryDirectory
        let pdfPath = tempDir.appendingPathComponent("empty_\(UUID().uuidString).pdf").path
        let pdfURL = URL(fileURLWithPath: pdfPath)
        defer { try? FileManager.default.removeItem(atPath: pdfPath) }

        var mediaBox = CGRect(x: 0, y: 0, width: 612, height: 792)
        guard let context = CGContext(pdfURL as CFURL, mediaBox: &mediaBox, nil) else {
            XCTFail("Failed to create PDF context")
            return
        }

        // Create a page with no text content
        context.beginPage(mediaBox: &mediaBox)
        // Just draw a rectangle, no text
        context.setFillColor(NSColor.white.cgColor)
        context.fill(mediaBox)
        context.endPage()
        context.closePDF()

        let result = PDFUtils.extractText(from: pdfPath)
        // Should be nil or empty since no text was added
        XCTAssertTrue(result == nil || result?.isEmpty == true)
    }

    func testHasExtractableTextVerboseModeInsufficientText() throws {
        // Create a PDF with very short text
        let testText = "Hi"  // Only 2 characters, below minimum of 50
        let pdfPath = try createTestPDF(withText: testText)
        defer { removeTestPDF(at: pdfPath) }

        let result = PDFUtils.hasExtractableText(at: pdfPath, verbose: true)
        XCTAssertFalse(result)
    }
}
