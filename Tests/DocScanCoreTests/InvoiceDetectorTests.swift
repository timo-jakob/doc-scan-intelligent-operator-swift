import AppKit
@testable import DocScanCore
import PDFKit
import XCTest

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
        modelName _: String?
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

    /// Embedded searchable PDF for testing (also shared with InvoiceDetectorAsyncTests)
    static let sharedSearchablePDFBase64 = """
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
        DocumentDetector(config: config)
    }

    private func createSearchablePDF() throws -> String {
        let pdfPath = tempDirectory.appendingPathComponent("test_invoice.pdf").path
        guard let pdfData = Data(
            base64Encoded: Self.sharedSearchablePDFBase64,
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

    func testGenerateFilenameSuccess() throws {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let date = try XCTUnwrap(dateFormatter.date(from: "2024-12-15"))

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

    func testCustomFilenamePattern() throws {
        // Note: DocumentDetector uses DocumentType's default pattern, not Configuration
        // This test verifies the invoice default pattern works
        let customConfig = Configuration()
        let customDetector = DocumentDetector(config: customConfig, documentType: .invoice)

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let date = try XCTUnwrap(dateFormatter.date(from: "2024-12-15"))

        let data = DocumentData(
            documentType: .invoice,
            isMatch: true,
            date: date,
            secondaryField: "TestCo"
        )
        let filename = customDetector.generateFilename(from: data)

        XCTAssertEqual(filename, "2024-12-15_Rechnung_TestCo.pdf")
    }

    func testCustomDateFormat() throws {
        let customConfig = Configuration(
            output: OutputSettings(dateFormat: "dd.MM.yyyy")
        )
        let customDetector = DocumentDetector(config: customConfig, documentType: .invoice)

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let date = try XCTUnwrap(dateFormatter.date(from: "2024-12-15"))

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
            "invoice number 12345",
        ]

        for text in testCases {
            let result = detector.categorizeWithDirectText(text)
            XCTAssertTrue(result.isMatch, "Should detect invoice in: \(text)")
        }
    }

    // MARK: - Pre-loaded TextLLM Initializer Tests

    func testDocumentDetectorInitWithPreloadedTextLLM() {
        let textLLM = TextLLMManager(config: config)
        let detectorWithTextLLM = DocumentDetector(
            config: config,
            documentType: .invoice,
            vlmProvider: mockVLM,
            textLLM: textLLM
        )

        XCTAssertEqual(detectorWithTextLLM.documentType, .invoice)
    }

    func testDocumentDetectorInitWithPreloadedTextLLMPrescription() {
        let textLLM = TextLLMManager(config: config)
        let detectorWithTextLLM = DocumentDetector(
            config: config,
            documentType: .prescription,
            vlmProvider: mockVLM,
            textLLM: textLLM
        )

        XCTAssertEqual(detectorWithTextLLM.documentType, .prescription)
    }

    func testDocumentDetectorInitWithPreloadedTextLLMGeneratesFilename() throws {
        let textLLM = TextLLMManager(config: config)
        let detectorWithTextLLM = DocumentDetector(
            config: config,
            documentType: .invoice,
            vlmProvider: mockVLM,
            textLLM: textLLM
        )

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let date = try XCTUnwrap(dateFormatter.date(from: "2025-01-15"))
        let data = DocumentData(
            documentType: .invoice,
            isMatch: true,
            date: date,
            secondaryField: "Test_Corp"
        )
        let filename = detectorWithTextLLM.generateFilename(from: data)
        XCTAssertEqual(filename, "2025-01-15_Rechnung_Test_Corp.pdf")
    }
}
