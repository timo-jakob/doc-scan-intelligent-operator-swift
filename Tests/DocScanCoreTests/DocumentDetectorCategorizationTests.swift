import AppKit
@testable import DocScanCore
import PDFKit
import XCTest

/// Tests for DocumentDetector's categorize() flow using mock providers.
/// Validates the parallel VLM + OCR categorization pipeline end-to-end.
final class DocumentDetectorCategorizationTests: XCTestCase {
    private var mockVLM: MockVLMProvider!
    private var mockTextLLM: MockTextLLMProvider!
    private var tempDir: URL!
    private var testPDFPath: String!

    override func setUp() {
        super.setUp()
        mockVLM = MockVLMProvider()
        mockTextLLM = MockTextLLMProvider()

        // Create a temporary directory and a minimal valid PDF for testing
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("DocumentDetectorTests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        testPDFPath = createTestPDF(containing: "Rechnung\nRechnungsnummer: 12345\nDatum: 2025-01-15\nFirma: Test GmbH")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    // MARK: - Phase 1: Categorization Agreement

    func testBothAgreeMatch() async throws {
        mockVLM.mockResponse = "YES"
        // PDF contains invoice keywords, so OCR/PDF text will also match

        let config = Configuration.defaultConfiguration
        let detector = DocumentDetector(
            config: config,
            documentType: .invoice,
            vlmProvider: mockVLM,
            textLLM: mockTextLLM
        )

        let (verification, context) = try await detector.categorize(pdfPath: testPDFPath)

        XCTAssertTrue(verification.bothAgree)
        XCTAssertEqual(verification.agreedIsMatch, true)
        XCTAssertTrue(verification.vlmResult.isMatch)
        XCTAssertTrue(verification.ocrResult.isMatch)
        XCTAssertFalse(context.ocrText.isEmpty)
    }

    func testBothAgreeNoMatch() async throws {
        mockVLM.mockResponse = "NO"
        // Create PDF without invoice keywords
        let noInvoicePDF = createTestPDF(containing: "Hello World. This is a random document with no relevant keywords at all.")

        let config = Configuration.defaultConfiguration
        let detector = DocumentDetector(
            config: config,
            documentType: .invoice,
            vlmProvider: mockVLM,
            textLLM: mockTextLLM
        )

        let (verification, _) = try await detector.categorize(pdfPath: noInvoicePDF)

        XCTAssertTrue(verification.bothAgree)
        XCTAssertEqual(verification.agreedIsMatch, false)
        XCTAssertFalse(verification.vlmResult.isMatch)
        XCTAssertFalse(verification.ocrResult.isMatch)
    }

    func testConflictVLMYesOCRNo() async throws {
        mockVLM.mockResponse = "YES"
        // PDF without invoice keywords → OCR says no
        let noInvoicePDF = createTestPDF(containing: "Hello World. This is a random document with no relevant keywords at all.")

        let config = Configuration.defaultConfiguration
        let detector = DocumentDetector(
            config: config,
            documentType: .invoice,
            vlmProvider: mockVLM,
            textLLM: mockTextLLM
        )

        let (verification, _) = try await detector.categorize(pdfPath: noInvoicePDF)

        XCTAssertFalse(verification.bothAgree)
        XCTAssertNil(verification.agreedIsMatch)
        XCTAssertTrue(verification.vlmResult.isMatch)
        XCTAssertFalse(verification.ocrResult.isMatch)
    }

    func testConflictVLMNoOCRYes() async throws {
        mockVLM.mockResponse = "NO"
        // PDF with invoice keywords → OCR says yes

        let config = Configuration.defaultConfiguration
        let detector = DocumentDetector(
            config: config,
            documentType: .invoice,
            vlmProvider: mockVLM,
            textLLM: mockTextLLM
        )

        let (verification, _) = try await detector.categorize(pdfPath: testPDFPath)

        XCTAssertFalse(verification.bothAgree)
        XCTAssertNil(verification.agreedIsMatch)
        XCTAssertFalse(verification.vlmResult.isMatch)
        XCTAssertTrue(verification.ocrResult.isMatch)
    }

    // MARK: - VLM Error Handling

    func testVLMErrorReturnsFalseMatch() async throws {
        mockVLM.shouldThrowError = true

        let config = Configuration.defaultConfiguration
        let detector = DocumentDetector(
            config: config,
            documentType: .invoice,
            vlmProvider: mockVLM,
            textLLM: mockTextLLM
        )

        let (verification, _) = try await detector.categorize(pdfPath: testPDFPath)

        // VLM error should result in isMatch=false with vlmError method
        XCTAssertFalse(verification.vlmResult.isMatch)
        XCTAssertEqual(verification.vlmResult.method, .vlmError)
        XCTAssertEqual(verification.vlmResult.confidence, .low)
        // OCR should still work independently
        XCTAssertTrue(verification.ocrResult.isMatch) // has invoice keywords
    }

    // MARK: - Phase 2: Extraction

    func testExtractDataWithEmptyContextThrows() async throws {
        let config = Configuration.defaultConfiguration
        let detector = DocumentDetector(
            config: config,
            documentType: .invoice,
            vlmProvider: mockVLM,
            textLLM: mockTextLLM
        )

        let emptyContext = CategorizationContext(ocrText: "", pdfPath: "/dummy.pdf")

        do {
            _ = try await detector.extractData(context: emptyContext)
            XCTFail("Expected extractionFailed error")
        } catch let error as DocScanError {
            if case .extractionFailed = error {
                // Expected
            } else {
                XCTFail("Expected extractionFailed, got \(error)")
            }
        }
    }

    func testExtractDataDelegatesToTextLLM() async throws {
        let expectedDate = DateUtils.parseDate("2025-03-15")
        mockTextLLM.mockDate = expectedDate
        mockTextLLM.mockSecondaryField = "Test_GmbH"

        let config = Configuration.defaultConfiguration
        let detector = DocumentDetector(
            config: config,
            documentType: .invoice,
            vlmProvider: mockVLM,
            textLLM: mockTextLLM
        )

        let context = CategorizationContext(ocrText: "Some invoice text", pdfPath: "/dummy.pdf")
        let result = try await detector.extractData(context: context)

        XCTAssertEqual(result.date, expectedDate)
        XCTAssertEqual(result.secondaryField, "Test_GmbH")
    }

    func testExtractDataTextLLMErrorPropagates() async throws {
        mockTextLLM.shouldThrowError = true

        let config = Configuration.defaultConfiguration
        let detector = DocumentDetector(
            config: config,
            documentType: .invoice,
            vlmProvider: mockVLM,
            textLLM: mockTextLLM
        )

        let context = CategorizationContext(ocrText: "Some invoice text", pdfPath: "/dummy.pdf")

        do {
            _ = try await detector.extractData(context: context)
            XCTFail("Expected error to propagate")
        } catch {
            // Error should propagate from TextLLM
            XCTAssertTrue(error is DocScanError)
        }
    }

    // MARK: - VLM Confidence Levels

    func testVLMHighConfidenceForExactYes() async throws {
        mockVLM.mockResponse = "yes"

        let config = Configuration.defaultConfiguration
        let detector = DocumentDetector(
            config: config,
            documentType: .invoice,
            vlmProvider: mockVLM,
            textLLM: mockTextLLM
        )

        let (verification, _) = try await detector.categorize(pdfPath: testPDFPath)

        XCTAssertEqual(verification.vlmResult.confidence, .high)
    }

    func testVLMMediumConfidenceForVerboseResponse() async throws {
        mockVLM.mockResponse = "yes, this appears to be an invoice"

        let config = Configuration.defaultConfiguration
        let detector = DocumentDetector(
            config: config,
            documentType: .invoice,
            vlmProvider: mockVLM,
            textLLM: mockTextLLM
        )

        let (verification, _) = try await detector.categorize(pdfPath: testPDFPath)

        XCTAssertTrue(verification.vlmResult.isMatch)
        XCTAssertEqual(verification.vlmResult.confidence, .medium)
    }

    // MARK: - Prescription Document Type

    func testPrescriptionCategorization() async throws {
        mockVLM.mockResponse = "YES"
        let prescriptionPDF = createTestPDF(containing: "Rezept\nVerordnung\nArzt: Dr. Mueller\nPZN: 12345678")

        let config = Configuration.defaultConfiguration
        let detector = DocumentDetector(
            config: config,
            documentType: .prescription,
            vlmProvider: mockVLM,
            textLLM: mockTextLLM
        )

        let (verification, _) = try await detector.categorize(pdfPath: prescriptionPDF)

        XCTAssertTrue(verification.bothAgree)
        XCTAssertEqual(verification.agreedIsMatch, true)
    }

    // MARK: - Helpers

    /// Creates a minimal searchable PDF with the given text content.
    private func createTestPDF(containing text: String) -> String {
        let pdfURL = tempDir.appendingPathComponent("\(UUID().uuidString).pdf")
        let pdfData = NSMutableData()
        var mediaBox = CGRect(x: 0, y: 0, width: 612, height: 792)

        guard let consumer = CGDataConsumer(data: pdfData as CFMutableData),
              let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil)
        else {
            fatalError("Failed to create PDF context")
        }

        context.beginPage(mediaBox: &mediaBox)

        // Draw text into the PDF
        let font = NSFont.systemFont(ofSize: 12)
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        let lines = text.components(separatedBy: "\n")
        for (index, line) in lines.enumerated() {
            let y = 750 - (index * 16)
            let attributedString = NSAttributedString(string: line, attributes: attributes)
            let frameSetter = CTFramesetterCreateWithAttributedString(attributedString)
            let path = CGPath(rect: CGRect(x: 50, y: y, width: 500, height: 20), transform: nil)
            let frame = CTFramesetterCreateFrame(frameSetter, CFRange(location: 0, length: 0), path, nil)
            CTFrameDraw(frame, context)
        }

        context.endPage()
        context.closePDF()

        try! pdfData.write(to: pdfURL)
        return pdfURL.path
    }
}
