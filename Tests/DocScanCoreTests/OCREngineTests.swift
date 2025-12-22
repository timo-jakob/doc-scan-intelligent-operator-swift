import XCTest
@testable import DocScanCore

final class OCREngineTests: XCTestCase {
    var engine: OCREngine!
    var config: Configuration!

    override func setUp() {
        super.setUp()
        config = Configuration.default
        engine = OCREngine(config: config)
    }

    func testDetectInvoiceWithKeywords() {
        let germanText = "Rechnung\nRechnungsnummer: 12345\nDatum: 2024-12-22"
        XCTAssertTrue(engine.detectInvoice(from: germanText))

        let englishText = "Invoice\nInvoice Number: 12345\nDate: 2024-12-22"
        XCTAssertTrue(engine.detectInvoice(from: englishText))

        let frenchText = "Facture\nNuméro de facture: 12345"
        XCTAssertTrue(engine.detectInvoice(from: frenchText))

        let nonInvoiceText = "This is just a regular document"
        XCTAssertFalse(engine.detectInvoice(from: nonInvoiceText))
    }

    func testExtractDateISO() {
        let text = "Invoice Date: 2024-12-22"
        let date = engine.extractDate(from: text)

        XCTAssertNotNil(date)
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month, .day], from: date!)
        XCTAssertEqual(components.year, 2024)
        XCTAssertEqual(components.month, 12)
        XCTAssertEqual(components.day, 22)
    }

    func testExtractDateEuropean() {
        let text = "Rechnungsdatum: 22.12.2024"
        let date = engine.extractDate(from: text)

        XCTAssertNotNil(date)
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month, .day], from: date!)
        XCTAssertEqual(components.year, 2024)
        XCTAssertEqual(components.month, 12)
        XCTAssertEqual(components.day, 22)
    }

    func testExtractDateNotFound() {
        let text = "This text has no date"
        let date = engine.extractDate(from: text)

        XCTAssertNil(date)
    }

    func testExtractCompanyWithKeywords() {
        let text = """
        Acme Corporation GmbH
        Musterstraße 123
        12345 Berlin
        """

        let company = engine.extractCompany(from: text)
        XCTAssertNotNil(company)
        XCTAssertTrue(company!.contains("Acme"))
    }

    func testExtractCompanyFirstLine() {
        let text = """
        My Company Name
        Some address
        Some city
        """

        let company = engine.extractCompany(from: text)
        XCTAssertEqual(company, "My Company Name")
    }

    func testExtractInvoiceDataComplete() {
        let text = """
        Acme Corp GmbH
        Rechnung
        Rechnungsdatum: 2024-12-22
        Rechnungsnummer: 12345
        """

        let (isInvoice, date, company) = engine.extractInvoiceData(from: text)

        XCTAssertTrue(isInvoice)
        XCTAssertNotNil(date)
        XCTAssertNotNil(company)
    }

    func testExtractInvoiceDataNotInvoice() {
        let text = "Just a regular document"

        let (isInvoice, date, company) = engine.extractInvoiceData(from: text)

        XCTAssertFalse(isInvoice)
        XCTAssertNil(date)
        XCTAssertNil(company)
    }
}
