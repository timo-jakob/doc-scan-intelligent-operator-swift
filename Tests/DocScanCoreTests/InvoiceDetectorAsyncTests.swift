import AppKit
@testable import DocScanCore
import PDFKit
import XCTest

// MARK: - Async Categorize Tests

final class InvoiceDetectorAsyncTests: XCTestCase {
    var detector: DocumentDetector!
    var config: Configuration!
    var tempDirectory: URL!
    var mockVLM: MockVLMProvider!

    override func setUp() {
        super.setUp()
        config = Configuration.defaultConfiguration
        mockVLM = MockVLMProvider()
        detector = DocumentDetector(config: config, vlmProvider: mockVLM)
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDirectory)
        mockVLM = nil
        super.tearDown()
    }

    func createSearchablePDF() throws -> String {
        let pdfPath = tempDirectory.appendingPathComponent("test_invoice.pdf").path
        guard let pdfData = Data(
            base64Encoded: InvoiceDetectorTests.sharedSearchablePDFBase64,
            options: .ignoreUnknownCharacters
        ) else {
            throw NSError(domain: "TestError", code: 1)
        }
        try pdfData.write(to: URL(fileURLWithPath: pdfPath))
        return pdfPath
    }

    func createEmptyPDF() throws -> String {
        let pdfPath = tempDirectory.appendingPathComponent("empty.pdf").path
        var mediaBox = CGRect(x: 0, y: 0, width: 612, height: 792)
        guard let context = CGContext(URL(fileURLWithPath: pdfPath) as CFURL, mediaBox: &mediaBox, nil) else {
            throw NSError(domain: "TestError", code: 1)
        }
        context.beginPage(mediaBox: &mediaBox)
        context.endPage()
        context.closePDF()
        return pdfPath
    }

    // Note: VLM model is not available in CI (MLX Metal library cannot be built via SPM).
    // However, the categorize() method has error handling that catches VLM failures
    // and returns fallback results, so these tests should complete successfully.
    // Early code paths (PDF validation, text extraction, image conversion) get covered.

    func testCategorizeWithInvalidPath() async {
        // Test that categorize() throws for non-existent file
        do {
            _ = try await detector.categorize(pdfPath: "/nonexistent/path/file.pdf")
            XCTFail("Should have thrown fileNotFound error")
        } catch let error as DocScanError {
            if case .fileNotFound = error {
                // Expected - PDF validation happens before VLM
            } else {
                XCTFail("Expected fileNotFound error, got: \(error)")
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    func testCategorizeWithInvalidPDFFile() async throws {
        // Test that categorize() throws for invalid PDF content
        let fakePDFPath = tempDirectory.appendingPathComponent("not_a_pdf.pdf").path
        try "This is not a PDF file".write(toFile: fakePDFPath, atomically: true, encoding: .utf8)

        do {
            _ = try await detector.categorize(pdfPath: fakePDFPath)
            XCTFail("Should have thrown invalidPDF error")
        } catch let error as DocScanError {
            if case .invalidPDF = error {
                // Expected - PDF validation happens before VLM
            } else {
                XCTFail("Expected invalidPDF error, got: \(error)")
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    // MARK: - Categorize with Mock VLM Tests

    func testCategorizeWithSearchablePDFVLMSaysYes() async throws {
        // Test categorize() with searchable PDF where VLM says YES
        let pdfPath = try createSearchablePDF()
        mockVLM.mockResponse = "YES"

        let result = try await detector.categorize(pdfPath: pdfPath)

        // VLM should have been called
        XCTAssertEqual(mockVLM.generateFromImageCallCount, 1)
        XCTAssertNotNil(mockVLM.lastPrompt)
        XCTAssertTrue(mockVLM.lastPrompt?.contains("INVOICE") ?? false)

        // Both VLM and OCR should agree it's an invoice (PDF contains "Rechnung")
        XCTAssertTrue(result.vlmResult.isMatch)
        XCTAssertTrue(result.ocrResult.isMatch)
        XCTAssertTrue(result.bothAgree)
        XCTAssertEqual(result.agreedIsMatch, true)

        // OCR should use direct PDF extraction
        XCTAssertEqual(result.ocrResult.method, .pdf)
    }

    func testCategorizeWithSearchablePDFVLMSaysNo() async throws {
        // Test categorize() with searchable PDF where VLM says NO (disagrees with OCR)
        let pdfPath = try createSearchablePDF()
        mockVLM.mockResponse = "NO"

        let result = try await detector.categorize(pdfPath: pdfPath)

        // VLM says no, OCR says yes (PDF contains "Rechnung")
        XCTAssertFalse(result.vlmResult.isMatch)
        XCTAssertTrue(result.ocrResult.isMatch)
        XCTAssertFalse(result.bothAgree)
        XCTAssertNil(result.agreedIsMatch)
    }

    func testCategorizeWithEmptyPDFThrowsError() async throws {
        // Test categorize() with empty PDF (no extractable text)
        // Empty PDFs cause OCR to throw "No text recognized" error
        let pdfPath = try createEmptyPDF()
        mockVLM.mockResponse = "NO"

        do {
            _ = try await detector.categorize(pdfPath: pdfPath)
            XCTFail("Should have thrown extractionFailed error for empty PDF")
        } catch let error as DocScanError {
            if case let .extractionFailed(message) = error {
                XCTAssertTrue(message.contains("No text recognized"))
            } else {
                XCTFail("Expected extractionFailed error, got: \(error)")
            }
        }

        // VLM should still have been called before OCR failed
        XCTAssertEqual(mockVLM.generateFromImageCallCount, 1)
    }

    func testCategorizeWithVLMError() async throws {
        // Test categorize() when VLM throws an error
        let pdfPath = try createSearchablePDF()
        mockVLM.shouldThrowError = true
        mockVLM.errorToThrow = DocScanError.inferenceError("Mock VLM error")

        let result = try await detector.categorize(pdfPath: pdfPath)

        // VLM should return error result
        XCTAssertFalse(result.vlmResult.isMatch)
        XCTAssertEqual(result.vlmResult.confidence, .low)
        XCTAssertTrue(result.vlmResult.method == .vlmError)

        // OCR should still work (PDF contains "Rechnung")
        XCTAssertTrue(result.ocrResult.isMatch)
        XCTAssertEqual(result.ocrResult.method, .pdf)

        // They disagree
        XCTAssertFalse(result.bothAgree)
    }

    func testCategorizeVerboseMode() async throws {
        // Test categorize() with verbose configuration
        let verboseConfig = Configuration(verbose: true)
        let verboseDetector = DocumentDetector(config: verboseConfig, documentType: .invoice, vlmProvider: mockVLM)
        let pdfPath = try createSearchablePDF()
        mockVLM.mockResponse = "YES"

        let result = try await verboseDetector.categorize(pdfPath: pdfPath)

        // Should complete successfully with verbose output
        XCTAssertTrue(result.vlmResult.isMatch)
        XCTAssertTrue(result.ocrResult.isMatch)
    }

    func testCategorizeVerboseModeEmptyPDF() async throws {
        // Test verbose mode with empty PDF (exercises OCR fallback verbose path)
        // Empty PDFs cause OCR to throw "No text recognized" error
        let verboseConfig = Configuration(verbose: true)
        let verboseDetector = DocumentDetector(config: verboseConfig, documentType: .invoice, vlmProvider: mockVLM)
        let pdfPath = try createEmptyPDF()
        mockVLM.mockResponse = "NO"

        do {
            _ = try await verboseDetector.categorize(pdfPath: pdfPath)
            XCTFail("Should have thrown extractionFailed error")
        } catch let error as DocScanError {
            if case let .extractionFailed(message) = error {
                XCTAssertTrue(message.contains("No text recognized"))
            } else {
                XCTFail("Expected extractionFailed error, got: \(error)")
            }
        }
    }

    func testCategorizeWithVLMTimeout() async throws {
        // Test categorize() when VLM times out
        let pdfPath = try createSearchablePDF()
        mockVLM.shouldThrowError = true
        mockVLM.errorToThrow = TimeoutError()

        let result = try await detector.categorize(pdfPath: pdfPath)

        // VLM should return timeout result
        XCTAssertFalse(result.vlmResult.isMatch)
        XCTAssertEqual(result.vlmResult.confidence, .low)
        XCTAssertTrue(result.vlmResult.method == .vlmTimeout)
        XCTAssertEqual(result.vlmResult.reason, "Timed out")

        // OCR should still work
        XCTAssertTrue(result.ocrResult.isMatch)
    }

    func testCategorizeDirectTextExtractionPath() async throws {
        // Test that direct text extraction is used for searchable PDFs
        let pdfPath = try createSearchablePDF()
        mockVLM.mockResponse = "YES"

        let result = try await detector.categorize(pdfPath: pdfPath)

        // OCR result should indicate PDF method (direct extraction)
        XCTAssertEqual(result.ocrResult.method, .pdf)
        XCTAssertTrue(result.ocrResult.isMatch)
        XCTAssertNotNil(result.ocrResult.reason)
    }

    func testCategorizeOCRFallbackPathThrowsForEmptyPDF() async throws {
        // Test that OCR fallback is used for empty PDFs
        // Empty PDFs throw an error because OCR finds no text
        let pdfPath = try createEmptyPDF()
        mockVLM.mockResponse = "NO"

        do {
            _ = try await detector.categorize(pdfPath: pdfPath)
            XCTFail("Should have thrown extractionFailed error")
        } catch let error as DocScanError {
            if case let .extractionFailed(message) = error {
                XCTAssertTrue(message.contains("No text recognized"))
            } else {
                XCTFail("Expected extractionFailed error, got: \(error)")
            }
        }
    }
}

// MARK: - Extract Data Tests (Sync)

extension InvoiceDetectorAsyncTests {
    func testExtractDataWithoutCategorization() async {
        // extractData should fail if categorize wasn't called first
        do {
            _ = try await detector.extractData()
            XCTFail("Should have thrown an error")
        } catch let error as DocScanError {
            if case let .extractionFailed(message) = error {
                XCTAssertTrue(message.contains("No OCR text"))
            } else {
                XCTFail("Expected extractionFailed error")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    // MARK: - Verbose Mode Coverage Tests

    func testCategorizeVerboseModeWithVLMTimeout() async throws {
        // Exercises the verbose print inside the VLM-timeout catch branch (lines 240-241)
        let verboseConfig = Configuration(verbose: true)
        let verboseDetector = DocumentDetector(config: verboseConfig, documentType: .invoice, vlmProvider: mockVLM)
        let pdfPath = try createSearchablePDF()
        mockVLM.shouldThrowError = true
        mockVLM.errorToThrow = TimeoutError()

        let result = try await verboseDetector.categorize(pdfPath: pdfPath)

        XCTAssertFalse(result.vlmResult.isMatch)
        XCTAssertTrue(result.vlmResult.isTimedOut)
        XCTAssertTrue(result.ocrResult.isMatch)
    }

    func testCategorizeVerboseModeWithVLMError() async throws {
        // Exercises the verbose print inside the VLM-error catch branch (lines 246-247)
        let verboseConfig = Configuration(verbose: true)
        let verboseDetector = DocumentDetector(config: verboseConfig, documentType: .invoice, vlmProvider: mockVLM)
        let pdfPath = try createSearchablePDF()
        mockVLM.shouldThrowError = true
        mockVLM.errorToThrow = DocScanError.inferenceError("Mock VLM error")

        let result = try await verboseDetector.categorize(pdfPath: pdfPath)

        XCTAssertFalse(result.vlmResult.isMatch)
        XCTAssertTrue(result.vlmResult.method == .vlmError)
        XCTAssertTrue(result.ocrResult.isMatch)
    }

    func testCategorizeVerboseModeConflict() async throws {
        // Exercises the verbose conflict print (lines 279-280): VLM=NO, OCR detects invoice keywords
        let verboseConfig = Configuration(verbose: true)
        let verboseDetector = DocumentDetector(config: verboseConfig, documentType: .invoice, vlmProvider: mockVLM)
        let pdfPath = try createSearchablePDF()
        mockVLM.mockResponse = "NO"

        let result = try await verboseDetector.categorize(pdfPath: pdfPath)

        XCTAssertFalse(result.vlmResult.isMatch)
        XCTAssertTrue(result.ocrResult.isMatch)
        XCTAssertFalse(result.bothAgree)
    }
}
