import XCTest
@testable import DocScanCore

final class InvoiceDetectorTests: XCTestCase {
    var detector: InvoiceDetector!
    var config: Configuration!

    override func setUp() {
        super.setUp()
        config = Configuration.defaultConfiguration
        detector = InvoiceDetector(config: config)
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
}
