import XCTest
import PDFKit
import AppKit
@testable import DocScanCore

// MARK: - Mock VLM Provider

/// Mock VLM provider for testing without actual model loading
final class MockVLMProvider: VLMProvider, @unchecked Sendable {
    /// Configure the mock response
    var mockResponse: String = "YES"
    var shouldThrowError: Bool = false
    var errorToThrow: Error = DocScanError.modelLoadFailed("Mock error")

    /// Track calls for verification
    private(set) var generateFromImageCallCount = 0
    private(set) var lastPrompt: String?
    private(set) var lastImage: NSImage?

    func generateFromImage(
        _ image: NSImage,
        prompt: String,
        modelName: String?
    ) async throws -> String {
        generateFromImageCallCount += 1
        lastPrompt = prompt
        lastImage = image

        if shouldThrowError {
            throw errorToThrow
        }

        return mockResponse
    }

    func reset() {
        generateFromImageCallCount = 0
        lastPrompt = nil
        lastImage = nil
        mockResponse = "YES"
        shouldThrowError = false
    }
}

// MARK: - Document Detector Tests

final class InvoiceDetectorTests: XCTestCase {
    var detector: DocumentDetector!
    var config: Configuration!
    var tempDirectory: URL!
    var mockVLM: MockVLMProvider!

    /// Embedded searchable PDF for testing
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

    /// Create detector without mock for tests that don't need VLM
    private func createDetectorWithoutMock() -> DocumentDetector {
        return DocumentDetector(config: config)
    }

    private func createSearchablePDF() throws -> String {
        let pdfPath = tempDirectory.appendingPathComponent("test_invoice.pdf").path
        guard let pdfData = Data(base64Encoded: Self.searchablePDFBase64, options: .ignoreUnknownCharacters) else {
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

    func testInvoiceDataInitialization() {
        let data = DocumentData(
            documentType: .invoice,
            isMatch: true,
            date: Date(),
            secondaryField: "Test Corp"
        )

        XCTAssertTrue(data.isMatch)
        XCTAssertNotNil(data.date)
        XCTAssertEqual(data.secondaryField, "Test Corp")
    }

    func testNotAnInvoice() {
        let data = DocumentData(
            documentType: .invoice,
            isMatch: false,
            date: nil,
            secondaryField: nil
        )

        XCTAssertFalse(data.isMatch)
        XCTAssertNil(data.date)
        XCTAssertNil(data.secondaryField)
    }

    func testGenerateFilenameSuccess() {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let date = dateFormatter.date(from: "2024-12-15")!

        let data = DocumentData(
            documentType: .invoice,
            isMatch: true,
            date: date,
            secondaryField: "Acme_Corp"
        )
        let filename = detector.generateFilename(from: data)

        XCTAssertEqual(filename, "2024-12-15_Rechnung_Acme_Corp.pdf")
    }

    func testGenerateFilenameNotAnInvoice() {
        let data = DocumentData(
            documentType: .invoice,
            isMatch: false,
            date: nil,
            secondaryField: nil
        )
        let filename = detector.generateFilename(from: data)

        XCTAssertNil(filename)
    }

    func testGenerateFilenameMissingData() {
        let data1 = DocumentData(
            documentType: .invoice,
            isMatch: true,
            date: Date(),
            secondaryField: nil
        )
        let filename1 = detector.generateFilename(from: data1)
        XCTAssertNil(filename1)

        let data2 = DocumentData(
            documentType: .invoice,
            isMatch: true,
            date: nil,
            secondaryField: "Test"
        )
        let filename2 = detector.generateFilename(from: data2)
        XCTAssertNil(filename2)
    }

    func testCustomFilenamePattern() {
        // Note: DocumentDetector uses DocumentType's default pattern, not Configuration
        // This test verifies the invoice default pattern works
        let customConfig = Configuration()
        let customDetector = DocumentDetector(config: customConfig, documentType: .invoice)

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let date = dateFormatter.date(from: "2024-12-15")!

        let data = DocumentData(
            documentType: .invoice,
            isMatch: true,
            date: date,
            secondaryField: "TestCo"
        )
        let filename = customDetector.generateFilename(from: data)

        XCTAssertEqual(filename, "2024-12-15_Rechnung_TestCo.pdf")
    }

    func testCustomDateFormat() {
        let customConfig = Configuration(
            output: OutputSettings(dateFormat: "dd.MM.yyyy")
        )
        let customDetector = DocumentDetector(config: customConfig, documentType: .invoice)

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let date = dateFormatter.date(from: "2024-12-15")!

        let data = DocumentData(
            documentType: .invoice,
            isMatch: true,
            date: date,
            secondaryField: "TestCo"
        )
        let filename = customDetector.generateFilename(from: data)

        XCTAssertEqual(filename, "15.12.2024_Rechnung_TestCo.pdf")
    }

    // MARK: - Direct Text Categorization Tests

    func testCategorizeWithDirectTextInvoice() {
        let invoiceText = """
        DB Fernverkehr AG
        Rechnung
        Rechnungsnummer: 2025018156792
        Datum: 27.06.2025
        Betrag: 81,90 €
        """

        let result = detector.categorizeWithDirectText(invoiceText)

        XCTAssertTrue(result.isMatch)
        XCTAssertEqual(result.method, "PDF")
        XCTAssertEqual(result.confidence, "high")
        XCTAssertNotNil(result.reason)
    }

    func testCategorizeWithDirectTextInvoiceGerman() {
        let invoiceText = """
        Rechnungsnummer: 12345
        Rechnungsdatum: 15.12.2024
        Gesamtbetrag: 150,00 EUR
        """

        let result = detector.categorizeWithDirectText(invoiceText)

        XCTAssertTrue(result.isMatch)
        XCTAssertEqual(result.method, "PDF")
        XCTAssertEqual(result.confidence, "high")
    }

    func testCategorizeWithDirectTextInvoiceEnglish() {
        let invoiceText = """
        Invoice Number: INV-2024-001
        Invoice Date: December 15, 2024
        Total Amount: $150.00
        """

        let result = detector.categorizeWithDirectText(invoiceText)

        XCTAssertTrue(result.isMatch)
        XCTAssertEqual(result.method, "PDF")
    }

    func testCategorizeWithDirectTextNotInvoice() {
        let regularText = """
        This is a regular document.
        It contains some text but nothing special.
        Just a normal letter or report.
        """

        let result = detector.categorizeWithDirectText(regularText)

        XCTAssertFalse(result.isMatch)
        XCTAssertEqual(result.method, "PDF")
        XCTAssertEqual(result.confidence, "high")
    }

    func testCategorizeWithDirectTextMediumConfidence() {
        // Only contains "Rechnung" but no strong indicators like "Rechnungsnummer"
        let invoiceText = """
        Vielen Dank für Ihre Rechnung.
        Wir werden diese bearbeiten.
        """

        let result = detector.categorizeWithDirectText(invoiceText)

        XCTAssertTrue(result.isMatch)
        XCTAssertEqual(result.method, "PDF")
        XCTAssertEqual(result.confidence, "medium")
    }

    func testCategorizeWithDirectTextEmptyString() {
        let result = detector.categorizeWithDirectText("")

        XCTAssertFalse(result.isMatch)
        XCTAssertEqual(result.method, "PDF")
    }

    func testCategorizeWithDirectTextFrench() {
        let invoiceText = """
        Facture
        Numéro de facture: 12345
        Date: 15/12/2024
        """

        let result = detector.categorizeWithDirectText(invoiceText)

        XCTAssertTrue(result.isMatch)
        XCTAssertEqual(result.method, "PDF")
    }

    func testCategorizeWithDirectTextReceipt() {
        let receiptText = """
        Receipt
        Thank you for your purchase
        Total: $25.00
        """

        let result = detector.categorizeWithDirectText(receiptText)

        XCTAssertTrue(result.isMatch)
        XCTAssertEqual(result.method, "PDF")
    }

    func testCategorizeWithDirectTextVerboseMode() {
        let verboseConfig = Configuration(verbose: true)
        let verboseDetector = DocumentDetector(config: verboseConfig, documentType: .invoice)

        let invoiceText = "Rechnung Nr. 12345"
        let result = verboseDetector.categorizeWithDirectText(invoiceText)

        // Should still work correctly in verbose mode
        XCTAssertTrue(result.isMatch)
        XCTAssertEqual(result.method, "PDF")
    }

    func testCategorizeWithDirectTextVerboseModeNotInvoice() {
        let verboseConfig = Configuration(verbose: true)
        let verboseDetector = DocumentDetector(config: verboseConfig, documentType: .invoice)

        // Regular text without any invoice keywords
        let regularText = "Lorem ipsum dolor sit amet, consectetur adipiscing elit."
        let result = verboseDetector.categorizeWithDirectText(regularText)

        XCTAssertFalse(result.isMatch)
        XCTAssertEqual(result.method, "PDF")
        XCTAssertEqual(result.confidence, "high")
    }

    func testCategorizeWithDirectTextVerboseModeWithReason() {
        let verboseConfig = Configuration(verbose: true)
        let verboseDetector = DocumentDetector(config: verboseConfig, documentType: .invoice)

        // Invoice text with strong indicators
        let invoiceText = """
        Rechnungsnummer: 12345
        Rechnungsdatum: 15.12.2024
        """
        let result = verboseDetector.categorizeWithDirectText(invoiceText)

        XCTAssertTrue(result.isMatch)
        XCTAssertNotNil(result.reason)
    }

    func testCategorizeWithDirectTextLongText() {
        let longText = String(repeating: "This is a test document. ", count: 100)
            + "Rechnung Nr. 12345"

        let result = detector.categorizeWithDirectText(longText)

        XCTAssertTrue(result.isMatch)
    }

    func testCategorizeWithDirectTextSpanish() {
        let invoiceText = """
        Factura
        Número de factura: FAC-2024-001
        Fecha: 15/12/2024
        """

        let result = detector.categorizeWithDirectText(invoiceText)

        XCTAssertTrue(result.isMatch)
        XCTAssertEqual(result.method, "PDF")
    }

    func testCategorizeWithDirectTextQuittung() {
        let receiptText = """
        Quittung
        Betrag: 50,00 EUR
        """

        let result = detector.categorizeWithDirectText(receiptText)

        XCTAssertTrue(result.isMatch)
    }

    func testCategorizeWithDirectTextCaseInsensitive() {
        let testCases = [
            "RECHNUNG NR 12345",
            "rechnung nr 12345",
            "Rechnung Nr 12345",
            "INVOICE NUMBER 12345",
            "invoice number 12345"
        ]

        for text in testCases {
            let result = detector.categorizeWithDirectText(text)
            XCTAssertTrue(result.isMatch, "Should detect invoice in: \(text)")
        }
    }

    // MARK: - CategorizationResult Tests

    func testCategorizationResultWithAllParameters() {
        let result = CategorizationResult(
            isMatch: true,
            confidence: "high",
            method: "VLM",
            reason: "Found invoice keywords"
        )

        XCTAssertTrue(result.isMatch)
        XCTAssertEqual(result.confidence, "high")
        XCTAssertEqual(result.method, "VLM")
        XCTAssertEqual(result.reason, "Found invoice keywords")
    }

    func testCategorizationResultDefaultValues() {
        let result = CategorizationResult(
            isMatch: false,
            method: "OCR"
        )

        XCTAssertFalse(result.isMatch)
        XCTAssertEqual(result.confidence, "high")
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

    func testDocumentDataWithCategorizationAgreement() {
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
        XCTAssertTrue(data.categorization!.bothAgree)
    }

    func testDocumentDataWithCategorizationDisagreement() {
        let vlm = CategorizationResult(isMatch: true, method: "VLM", reason: "Visual analysis")
        let ocr = CategorizationResult(isMatch: false, method: "OCR", reason: "No keywords found")
        let categorization = CategorizationVerification(vlmResult: vlm, ocrResult: ocr)

        let data = DocumentData(
            documentType: .invoice,
            isMatch: true,  // User resolved in favor of VLM
            date: Date(),
            secondaryField: "Test Corp",
            categorization: categorization
        )

        XCTAssertTrue(data.isMatch)
        XCTAssertNotNil(data.categorization)
        XCTAssertFalse(data.categorization!.bothAgree)
        XCTAssertNil(data.categorization!.agreedIsMatch)
    }

    // MARK: - Async Categorize Tests
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
        XCTAssertEqual(result.ocrResult.method, "PDF")
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
            if case .extractionFailed(let message) = error {
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
        XCTAssertEqual(result.vlmResult.confidence, "low")
        XCTAssertTrue(result.vlmResult.method.contains("error"))

        // OCR should still work (PDF contains "Rechnung")
        XCTAssertTrue(result.ocrResult.isMatch)
        XCTAssertEqual(result.ocrResult.method, "PDF")

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
            if case .extractionFailed(let message) = error {
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
        XCTAssertEqual(result.vlmResult.confidence, "low")
        XCTAssertTrue(result.vlmResult.method.contains("timeout"))
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
        XCTAssertEqual(result.ocrResult.method, "PDF")
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
            if case .extractionFailed(let message) = error {
                XCTAssertTrue(message.contains("No text recognized"))
            } else {
                XCTFail("Expected extractionFailed error, got: \(error)")
            }
        }
    }

    // MARK: - Extract Data Tests (Sync)

    func testExtractDataWithoutCategorization() async {
        // extractData should fail if categorize wasn't called first
        do {
            _ = try await detector.extractData()
            XCTFail("Should have thrown an error")
        } catch let error as DocScanError {
            if case .extractionFailed(let message) = error {
                XCTAssertTrue(message.contains("No OCR text"))
            } else {
                XCTFail("Expected extractionFailed error")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
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

    func testGenerateFilenameWithSpecialCharacters() {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let date = dateFormatter.date(from: "2024-12-15")!

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

    // MARK: - Prescription Document Type Tests

    func testPrescriptionDetector() {
        let prescriptionDetector = DocumentDetector(config: config, documentType: .prescription)
        XCTAssertEqual(prescriptionDetector.documentType, .prescription)
    }

    func testPrescriptionKeywordDetection() {
        let prescriptionDetector = DocumentDetector(config: config, documentType: .prescription)
        let prescriptionText = """
        Rezept
        Dr. med. Gesine Kaiser
        Patient: Max Mustermann
        Medikament: Ibuprofen 400mg
        """

        let result = prescriptionDetector.categorizeWithDirectText(prescriptionText)

        XCTAssertTrue(result.isMatch)
        XCTAssertEqual(result.method, "PDF")
    }

    func testPrescriptionFilenameGeneration() {
        let prescriptionDetector = DocumentDetector(config: config, documentType: .prescription)

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let date = dateFormatter.date(from: "2024-12-15")!

        let data = DocumentData(
            documentType: .prescription,
            isMatch: true,
            date: date,
            secondaryField: "Gesine_Kaiser",
            patientName: "Penelope"
        )
        let filename = prescriptionDetector.generateFilename(from: data)

        XCTAssertEqual(filename, "2024-12-15_Rezept_für_Penelope_von_Gesine_Kaiser.pdf")
    }

    func testPrescriptionFilenameGenerationWithoutPatient() {
        let prescriptionDetector = DocumentDetector(config: config, documentType: .prescription)

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let date = dateFormatter.date(from: "2024-12-15")!

        // No patient name - should fallback to simpler pattern
        let data = DocumentData(
            documentType: .prescription,
            isMatch: true,
            date: date,
            secondaryField: "Gesine_Kaiser",
            patientName: nil
        )
        let filename = prescriptionDetector.generateFilename(from: data)

        XCTAssertEqual(filename, "2024-12-15_Rezept_von_Gesine_Kaiser.pdf")
    }

    func testPrescriptionFilenameGenerationWithoutDoctor() {
        let prescriptionDetector = DocumentDetector(config: config, documentType: .prescription)

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let date = dateFormatter.date(from: "2024-12-15")!

        // No doctor name - should fallback to pattern without doctor
        let data = DocumentData(
            documentType: .prescription,
            isMatch: true,
            date: date,
            secondaryField: nil,
            patientName: "Penelope"
        )
        let filename = prescriptionDetector.generateFilename(from: data)

        XCTAssertEqual(filename, "2024-12-15_Rezept_für_Penelope.pdf")
    }

    func testPrescriptionFilenameGenerationWithoutPatientAndDoctor() {
        let prescriptionDetector = DocumentDetector(config: config, documentType: .prescription)

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let date = dateFormatter.date(from: "2024-12-15")!

        // Neither patient nor doctor - minimal pattern
        let data = DocumentData(
            documentType: .prescription,
            isMatch: true,
            date: date,
            secondaryField: nil,
            patientName: nil
        )
        let filename = prescriptionDetector.generateFilename(from: data)

        XCTAssertEqual(filename, "2024-12-15_Rezept.pdf")
    }

    func testDocumentDataForPrescription() {
        let data = DocumentData(
            documentType: .prescription,
            isMatch: true,
            date: Date(),
            secondaryField: "Gesine Kaiser"
        )

        XCTAssertEqual(data.documentType, .prescription)
        XCTAssertTrue(data.isMatch)
        XCTAssertEqual(data.secondaryField, "Gesine Kaiser")
    }
}
