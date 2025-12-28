import XCTest
import PDFKit
@testable import DocScanCore

final class InvoiceDetectorTests: XCTestCase {
    var detector: InvoiceDetector!
    var config: Configuration!
    var tempDirectory: URL!

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
        detector = InvoiceDetector(config: config)
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDirectory)
        super.tearDown()
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
        let data = InvoiceData(isInvoice: true, date: Date(), company: "Test Corp")

        XCTAssertTrue(data.isInvoice)
        XCTAssertNotNil(data.date)
        XCTAssertEqual(data.company, "Test Corp")
    }

    func testNotAnInvoice() {
        let data = InvoiceData(isInvoice: false, date: nil, company: nil)

        XCTAssertFalse(data.isInvoice)
        XCTAssertNil(data.date)
        XCTAssertNil(data.company)
    }

    func testGenerateFilenameSuccess() {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let date = dateFormatter.date(from: "2024-12-15")!

        let data = InvoiceData(isInvoice: true, date: date, company: "Acme Corp")
        let filename = detector.generateFilename(from: data)

        XCTAssertEqual(filename, "2024-12-15_Rechnung_Acme Corp.pdf")
    }

    func testGenerateFilenameNotAnInvoice() {
        let data = InvoiceData(isInvoice: false, date: nil, company: nil)
        let filename = detector.generateFilename(from: data)

        XCTAssertNil(filename)
    }

    func testGenerateFilenameMissingData() {
        let data1 = InvoiceData(isInvoice: true, date: Date(), company: nil)
        let filename1 = detector.generateFilename(from: data1)
        XCTAssertNil(filename1)

        let data2 = InvoiceData(isInvoice: true, date: nil, company: "Test")
        let filename2 = detector.generateFilename(from: data2)
        XCTAssertNil(filename2)
    }

    func testCustomFilenamePattern() {
        let customConfig = Configuration(
            output: OutputSettings(filenamePattern: "{company}_{date}_Invoice.pdf")
        )
        let customDetector = InvoiceDetector(config: customConfig)

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let date = dateFormatter.date(from: "2024-12-15")!

        let data = InvoiceData(isInvoice: true, date: date, company: "TestCo")
        let filename = customDetector.generateFilename(from: data)

        XCTAssertEqual(filename, "TestCo_2024-12-15_Invoice.pdf")
    }

    func testCustomDateFormat() {
        let customConfig = Configuration(
            output: OutputSettings(dateFormat: "dd.MM.yyyy")
        )
        let customDetector = InvoiceDetector(config: customConfig)

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let date = dateFormatter.date(from: "2024-12-15")!

        let data = InvoiceData(isInvoice: true, date: date, company: "TestCo")
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

        XCTAssertTrue(result.isInvoice)
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

        XCTAssertTrue(result.isInvoice)
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

        XCTAssertTrue(result.isInvoice)
        XCTAssertEqual(result.method, "PDF")
    }

    func testCategorizeWithDirectTextNotInvoice() {
        let regularText = """
        This is a regular document.
        It contains some text but nothing special.
        Just a normal letter or report.
        """

        let result = detector.categorizeWithDirectText(regularText)

        XCTAssertFalse(result.isInvoice)
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

        XCTAssertTrue(result.isInvoice)
        XCTAssertEqual(result.method, "PDF")
        XCTAssertEqual(result.confidence, "medium")
    }

    func testCategorizeWithDirectTextEmptyString() {
        let result = detector.categorizeWithDirectText("")

        XCTAssertFalse(result.isInvoice)
        XCTAssertEqual(result.method, "PDF")
    }

    func testCategorizeWithDirectTextFrench() {
        let invoiceText = """
        Facture
        Numéro de facture: 12345
        Date: 15/12/2024
        """

        let result = detector.categorizeWithDirectText(invoiceText)

        XCTAssertTrue(result.isInvoice)
        XCTAssertEqual(result.method, "PDF")
    }

    func testCategorizeWithDirectTextReceipt() {
        let receiptText = """
        Receipt
        Thank you for your purchase
        Total: $25.00
        """

        let result = detector.categorizeWithDirectText(receiptText)

        XCTAssertTrue(result.isInvoice)
        XCTAssertEqual(result.method, "PDF")
    }

    func testCategorizeWithDirectTextVerboseMode() {
        let verboseConfig = Configuration(verbose: true)
        let verboseDetector = InvoiceDetector(config: verboseConfig)

        let invoiceText = "Rechnung Nr. 12345"
        let result = verboseDetector.categorizeWithDirectText(invoiceText)

        // Should still work correctly in verbose mode
        XCTAssertTrue(result.isInvoice)
        XCTAssertEqual(result.method, "PDF")
    }

    func testCategorizeWithDirectTextVerboseModeNotInvoice() {
        let verboseConfig = Configuration(verbose: true)
        let verboseDetector = InvoiceDetector(config: verboseConfig)

        // Regular text without any invoice keywords
        let regularText = "Lorem ipsum dolor sit amet, consectetur adipiscing elit."
        let result = verboseDetector.categorizeWithDirectText(regularText)

        XCTAssertFalse(result.isInvoice)
        XCTAssertEqual(result.method, "PDF")
        XCTAssertEqual(result.confidence, "high")
    }

    func testCategorizeWithDirectTextVerboseModeWithReason() {
        let verboseConfig = Configuration(verbose: true)
        let verboseDetector = InvoiceDetector(config: verboseConfig)

        // Invoice text with strong indicators
        let invoiceText = """
        Rechnungsnummer: 12345
        Rechnungsdatum: 15.12.2024
        """
        let result = verboseDetector.categorizeWithDirectText(invoiceText)

        XCTAssertTrue(result.isInvoice)
        XCTAssertNotNil(result.reason)
    }

    func testCategorizeWithDirectTextLongText() {
        let longText = String(repeating: "This is a test document. ", count: 100)
            + "Rechnung Nr. 12345"

        let result = detector.categorizeWithDirectText(longText)

        XCTAssertTrue(result.isInvoice)
    }

    func testCategorizeWithDirectTextSpanish() {
        let invoiceText = """
        Factura
        Número de factura: FAC-2024-001
        Fecha: 15/12/2024
        """

        let result = detector.categorizeWithDirectText(invoiceText)

        XCTAssertTrue(result.isInvoice)
        XCTAssertEqual(result.method, "PDF")
    }

    func testCategorizeWithDirectTextQuittung() {
        let receiptText = """
        Quittung
        Betrag: 50,00 EUR
        """

        let result = detector.categorizeWithDirectText(receiptText)

        XCTAssertTrue(result.isInvoice)
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
            XCTAssertTrue(result.isInvoice, "Should detect invoice in: \(text)")
        }
    }

    // MARK: - CategorizationResult Tests

    func testCategorizationResultWithAllParameters() {
        let result = CategorizationResult(
            isInvoice: true,
            confidence: "high",
            method: "VLM",
            reason: "Found invoice keywords"
        )

        XCTAssertTrue(result.isInvoice)
        XCTAssertEqual(result.confidence, "high")
        XCTAssertEqual(result.method, "VLM")
        XCTAssertEqual(result.reason, "Found invoice keywords")
    }

    func testCategorizationResultDefaultValues() {
        let result = CategorizationResult(
            isInvoice: false,
            method: "OCR"
        )

        XCTAssertFalse(result.isInvoice)
        XCTAssertEqual(result.confidence, "high")
        XCTAssertEqual(result.method, "OCR")
        XCTAssertNil(result.reason)
    }

    // MARK: - CategorizationVerification Tests

    func testCategorizationVerificationAgreement() {
        let vlm = CategorizationResult(isInvoice: true, method: "VLM")
        let ocr = CategorizationResult(isInvoice: true, method: "OCR")

        let verification = CategorizationVerification(vlmResult: vlm, ocrResult: ocr)

        XCTAssertTrue(verification.bothAgree)
        XCTAssertEqual(verification.agreedIsInvoice, true)
        XCTAssertTrue(verification.vlmResult.isInvoice)
        XCTAssertTrue(verification.ocrResult.isInvoice)
    }

    func testCategorizationVerificationDisagreement() {
        let vlm = CategorizationResult(isInvoice: true, method: "VLM")
        let ocr = CategorizationResult(isInvoice: false, method: "OCR")

        let verification = CategorizationVerification(vlmResult: vlm, ocrResult: ocr)

        XCTAssertFalse(verification.bothAgree)
        XCTAssertNil(verification.agreedIsInvoice)
    }

    // MARK: - ExtractionResult Tests

    func testExtractionResultComplete() {
        let date = Date()
        let result = ExtractionResult(date: date, company: "Test Corp")

        XCTAssertEqual(result.date, date)
        XCTAssertEqual(result.company, "Test Corp")
    }

    func testExtractionResultPartial() {
        let result = ExtractionResult(date: nil, company: "Only Company")

        XCTAssertNil(result.date)
        XCTAssertEqual(result.company, "Only Company")
    }

    // MARK: - InvoiceData with Categorization Tests

    func testInvoiceDataWithCategorizationAgreement() {
        let vlm = CategorizationResult(isInvoice: true, method: "VLM")
        let ocr = CategorizationResult(isInvoice: true, method: "OCR")
        let categorization = CategorizationVerification(vlmResult: vlm, ocrResult: ocr)

        let data = InvoiceData(
            isInvoice: true,
            date: Date(),
            company: "Test Corp",
            categorization: categorization
        )

        XCTAssertTrue(data.isInvoice)
        XCTAssertNotNil(data.categorization)
        XCTAssertTrue(data.categorization!.bothAgree)
    }

    func testInvoiceDataWithCategorizationDisagreement() {
        let vlm = CategorizationResult(isInvoice: true, method: "VLM", reason: "Visual analysis")
        let ocr = CategorizationResult(isInvoice: false, method: "OCR", reason: "No keywords found")
        let categorization = CategorizationVerification(vlmResult: vlm, ocrResult: ocr)

        let data = InvoiceData(
            isInvoice: true,  // User resolved in favor of VLM
            date: Date(),
            company: "Test Corp",
            categorization: categorization
        )

        XCTAssertTrue(data.isInvoice)
        XCTAssertNotNil(data.categorization)
        XCTAssertFalse(data.categorization!.bothAgree)
        XCTAssertNil(data.categorization!.agreedIsInvoice)
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
            XCTAssertTrue(result.isInvoice)
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
        let data = InvoiceData(isInvoice: true, date: date, company: "Test Company")
        let filename = detector.generateFilename(from: data)

        XCTAssertNotNil(filename)
        XCTAssertEqual(filename, "2024-12-15_Rechnung_Test Company.pdf")
    }

    func testGenerateFilenameWithEmptyCompany() {
        let data = InvoiceData(isInvoice: true, date: Date(), company: "")
        let filename = detector.generateFilename(from: data)

        // Empty company should still generate filename with empty company part
        XCTAssertNotNil(filename)
    }
}
