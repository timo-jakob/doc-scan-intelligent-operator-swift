import AppKit
@testable import DocScanCore
import PDFKit
import XCTest

// MARK: - PDF Validation and Integration Tests

final class InvoiceDetectorIntegrationTests: XCTestCase {
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

    private func createSearchablePDF() throws -> String {
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

    private func createEmptyPDF() throws -> String {
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

    // MARK: - CategorizationResult Tests

    func testCategorizationResultWithAllParameters() {
        let result = CategorizationResult(
            isMatch: true,
            confidence: .high,
            method: "VLM",
            reason: "Found invoice keywords"
        )

        XCTAssertTrue(result.isMatch)
        XCTAssertEqual(result.confidence, .high)
        XCTAssertEqual(result.method, "VLM")
        XCTAssertEqual(result.reason, "Found invoice keywords")
    }

    func testCategorizationResultDefaultValues() {
        let result = CategorizationResult(
            isMatch: false,
            method: "OCR"
        )

        XCTAssertFalse(result.isMatch)
        XCTAssertEqual(result.confidence, .high)
        XCTAssertEqual(result.method, "OCR")
        XCTAssertNil(result.reason)
    }

    // MARK: - CategorizationVerification Tests

    func testCategorizationVerificationAgreement() {
        let vlm = CategorizationResult(isMatch: true, method: "VLM")
        let ocr = CategorizationResult(isMatch: true, method: "OCR")

        let verification = CategorizationVerification(vlmResult: vlm, ocrResult: ocr)

        XCTAssertTrue(verification.bothAgree)
        XCTAssertEqual(verification.agreedIsMatch, true)
        XCTAssertTrue(verification.vlmResult.isMatch)
        XCTAssertTrue(verification.ocrResult.isMatch)
    }

    func testCategorizationVerificationDisagreement() {
        let vlm = CategorizationResult(isMatch: true, method: "VLM")
        let ocr = CategorizationResult(isMatch: false, method: "OCR")

        let verification = CategorizationVerification(vlmResult: vlm, ocrResult: ocr)

        XCTAssertFalse(verification.bothAgree)
        XCTAssertNil(verification.agreedIsMatch)
    }

    // MARK: - ExtractionResult Tests

    func testExtractionResultComplete() {
        let date = Date()
        let result = ExtractionResult(date: date, secondaryField: "Test Corp")

        XCTAssertEqual(result.date, date)
        XCTAssertEqual(result.secondaryField, "Test Corp")
    }

    func testExtractionResultPartial() {
        let result = ExtractionResult(date: nil, secondaryField: "Only Company")

        XCTAssertNil(result.date)
        XCTAssertEqual(result.secondaryField, "Only Company")
        XCTAssertNil(result.patientName)
    }

    func testExtractionResultWithPatientName() {
        let date = Date()
        let result = ExtractionResult(date: date, secondaryField: "Dr. Kaiser", patientName: "Penelope")

        XCTAssertEqual(result.date, date)
        XCTAssertEqual(result.secondaryField, "Dr. Kaiser")
        XCTAssertEqual(result.patientName, "Penelope")
    }

    // MARK: - DocumentData with Categorization Tests

    func testDocumentDataWithCategorizationAgreement() throws {
        let vlm = CategorizationResult(isMatch: true, method: "VLM")
        let ocr = CategorizationResult(isMatch: true, method: "OCR")
        let categorization = CategorizationVerification(vlmResult: vlm, ocrResult: ocr)

        let data = DocumentData(
            documentType: .invoice,
            isMatch: true,
            date: Date(),
            secondaryField: "Test Corp",
            categorization: categorization
        )

        XCTAssertTrue(data.isMatch)
        XCTAssertNotNil(data.categorization)
        XCTAssertTrue(try XCTUnwrap(data.categorization?.bothAgree))
    }

    func testDocumentDataWithCategorizationDisagreement() throws {
        let vlm = CategorizationResult(isMatch: true, method: "VLM", reason: "Visual analysis")
        let ocr = CategorizationResult(isMatch: false, method: "OCR", reason: "No keywords found")
        let categorization = CategorizationVerification(vlmResult: vlm, ocrResult: ocr)

        let data = DocumentData(
            documentType: .invoice,
            isMatch: true, // User resolved in favor of VLM
            date: Date(),
            secondaryField: "Test Corp",
            categorization: categorization
        )

        XCTAssertTrue(data.isMatch)
        XCTAssertNotNil(data.categorization)
        XCTAssertFalse(try XCTUnwrap(data.categorization?.bothAgree))
        XCTAssertNil(data.categorization?.agreedIsMatch)
    }

    // MARK: - PDF Validation Tests (Sync via PDFUtils)

    func testValidatePDFWithInvalidPath() {
        // Test that PDFUtils.validatePDF throws for non-existent file
        XCTAssertThrowsError(try PDFUtils.validatePDF(at: "/nonexistent/file.pdf")) { error in
            guard let docScanError = error as? DocScanError else {
                XCTFail("Expected DocScanError")
                return
            }
            if case .fileNotFound = docScanError {
                // Expected
            } else {
                XCTFail("Expected fileNotFound error")
            }
        }
    }

    func testValidatePDFWithInvalidFile() throws {
        // Create a non-PDF file with .pdf extension
        let fakePDFPath = tempDirectory.appendingPathComponent("fake.pdf").path
        try "This is not a PDF".write(toFile: fakePDFPath, atomically: true, encoding: .utf8)

        XCTAssertThrowsError(try PDFUtils.validatePDF(at: fakePDFPath)) { error in
            guard let docScanError = error as? DocScanError else {
                XCTFail("Expected DocScanError")
                return
            }
            if case .invalidPDF = docScanError {
                // Expected
            } else {
                XCTFail("Expected invalidPDF error")
            }
        }
    }

    func testValidatePDFWithValidFile() throws {
        let pdfPath = try createSearchablePDF()
        XCTAssertNoThrow(try PDFUtils.validatePDF(at: pdfPath))
    }

    // MARK: - Direct Text Extraction Integration Tests

    func testDirectTextExtractionWithSearchablePDF() throws {
        let pdfPath = try createSearchablePDF()

        // Extract text using PDFUtils
        let text = PDFUtils.extractText(from: pdfPath)
        XCTAssertNotNil(text)
        XCTAssertTrue(text?.contains("Rechnung") ?? false)

        // Test categorization with extracted text
        if let extractedText = text {
            let result = detector.categorizeWithDirectText(extractedText)
            XCTAssertTrue(result.isMatch)
            XCTAssertEqual(result.method, "PDF")
        }
    }

    func testDirectTextExtractionWithEmptyPDF() throws {
        let pdfPath = try createEmptyPDF()

        // Extract text from empty PDF - should return nil or empty
        let text = PDFUtils.extractText(from: pdfPath)
        let isEmpty = text == nil || text!.isEmpty || text!.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        // If some text is extracted, it should be below minimum threshold
        if let extractedText = text, !extractedText.isEmpty {
            XCTAssertLessThan(extractedText.count, PDFUtils.minimumTextLength)
        } else {
            XCTAssertTrue(isEmpty)
        }
    }

    func testHasExtractableTextWithSearchablePDF() throws {
        let pdfPath = try createSearchablePDF()
        XCTAssertTrue(PDFUtils.hasExtractableText(at: pdfPath))
    }

    func testHasExtractableTextWithEmptyPDF() throws {
        let pdfPath = try createEmptyPDF()
        XCTAssertFalse(PDFUtils.hasExtractableText(at: pdfPath))
    }

    // MARK: - Generate Filename Edge Cases

    func testGenerateFilenameWithSpecialCharacters() throws {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let date = try XCTUnwrap(dateFormatter.date(from: "2024-12-15"))

        // Note: generateFilename doesn't sanitize the company name - that happens
        // earlier in the flow via StringUtils.sanitizeCompanyName
        // This test verifies generateFilename works with any company name
        let data = DocumentData(
            documentType: .invoice,
            isMatch: true,
            date: date,
            secondaryField: "Test_Company"
        )
        let filename = detector.generateFilename(from: data)

        XCTAssertNotNil(filename)
        XCTAssertEqual(filename, "2024-12-15_Rechnung_Test_Company.pdf")
    }

    func testGenerateFilenameWithEmptyCompany() {
        let data = DocumentData(
            documentType: .invoice,
            isMatch: true,
            date: Date(),
            secondaryField: ""
        )
        let filename = detector.generateFilename(from: data)

        // Empty company should still generate filename with empty company part
        XCTAssertNotNil(filename)
    }
}
