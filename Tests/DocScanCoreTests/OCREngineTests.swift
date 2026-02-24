@testable import DocScanCore
import Vision
import XCTest

final class OCREngineTests: XCTestCase {
    var engine: OCREngine!
    var config: Configuration!

    override func setUp() {
        super.setUp()
        config = Configuration.defaultConfiguration
        engine = OCREngine(config: config)
    }

    // MARK: - Extract Text From Observations Tests

    func testExtractTextFromObservationsEmpty() {
        // Test with empty observations array
        let result = OCREngine.extractTextFromObservations([])
        XCTAssertEqual(result, "")
    }

    // MARK: - Invoice Detection Tests

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

    func testDetectInvoiceKeywordsWithConfidence() {
        // Strong indicators (high confidence)
        let strongText = "Rechnungsnummer: 12345"
        let result1 = engine.detectInvoiceKeywords(from: strongText)
        XCTAssertTrue(result1.isMatch)
        XCTAssertEqual(result1.confidence, .high)
        XCTAssertNotNil(result1.reason)

        // Medium indicators
        let mediumText = "Rechnung für Dienstleistungen"
        let result2 = engine.detectInvoiceKeywords(from: mediumText)
        XCTAssertTrue(result2.isMatch)
        XCTAssertEqual(result2.confidence, .medium)

        // No invoice keywords
        let noInvoiceText = "Just a regular document"
        let result3 = engine.detectInvoiceKeywords(from: noInvoiceText)
        XCTAssertFalse(result3.isMatch)
        XCTAssertEqual(result3.confidence, .high) // High confidence it's NOT an invoice
    }

    // MARK: - Date Extraction Tests

    func testExtractDateISO() throws {
        let text = "Invoice Date: 2024-12-22"
        let date = engine.extractDate(from: text)

        XCTAssertNotNil(date)
        let calendar = Calendar.current
        let components = try calendar.dateComponents([.year, .month, .day], from: XCTUnwrap(date))
        XCTAssertEqual(components.year, 2024)
        XCTAssertEqual(components.month, 12)
        XCTAssertEqual(components.day, 22)
    }

    func testExtractDateEuropean() throws {
        let text = "Rechnungsdatum: 22.12.2024"
        let date = engine.extractDate(from: text)

        XCTAssertNotNil(date)
        let calendar = Calendar.current
        let components = try calendar.dateComponents([.year, .month, .day], from: XCTUnwrap(date))
        XCTAssertEqual(components.year, 2024)
        XCTAssertEqual(components.month, 12)
        XCTAssertEqual(components.day, 22)
    }

    func testExtractDateNotFound() {
        let text = "This text has no date"
        let date = engine.extractDate(from: text)

        XCTAssertNil(date)
    }

    func testExtractDateColonSeparated() throws {
        // OCR sometimes reads dots as colons
        let text = "Datum:13:11:2025"
        let date = engine.extractDate(from: text)

        XCTAssertNotNil(date)
        let calendar = Calendar.current
        let components = try calendar.dateComponents([.year, .month, .day], from: XCTUnwrap(date))
        XCTAssertEqual(components.year, 2025)
        XCTAssertEqual(components.month, 11)
        XCTAssertEqual(components.day, 13)
    }

    func testExtractDateGermanMonth() throws {
        let text = "Beitragsrechnung September 2022"
        let date = engine.extractDate(from: text)

        XCTAssertNotNil(date)
        let calendar = Calendar.current
        let components = try calendar.dateComponents([.year, .month, .day], from: XCTUnwrap(date))
        XCTAssertEqual(components.year, 2022)
        XCTAssertEqual(components.month, 9)
        XCTAssertEqual(components.day, 1) // First of month for month-only dates
    }

    func testExtractDateGermanMonthAbbreviated() throws {
        let text = "Rechnung Okt 2023"
        let date = engine.extractDate(from: text)

        XCTAssertNotNil(date)
        let calendar = Calendar.current
        let components = try calendar.dateComponents([.year, .month, .day], from: XCTUnwrap(date))
        XCTAssertEqual(components.year, 2023)
        XCTAssertEqual(components.month, 10)
    }

    func testExtractDateGermanMonthWordBoundary() {
        // "mai" should not match within "email"
        let textWithEmail = "Contact: info@company.com or email 2023"
        let dateFromEmail = engine.extractDate(from: textWithEmail)
        XCTAssertNil(dateFromEmail, "Should not match 'mai' within 'email'")

        // "jan" should not match within "january" when looking for German abbreviation
        // (but "januar" should still work as full German month)
        let textWithJanuar = "Rechnung Januar 2023"
        let dateFromJanuar = engine.extractDate(from: textWithJanuar)
        XCTAssertNotNil(dateFromJanuar, "Should match 'januar' as complete word")

        // Standalone "mai" should still work
        let textWithMai = "Rechnung Mai 2023"
        let dateFromMai = engine.extractDate(from: textWithMai)
        XCTAssertNotNil(dateFromMai, "Should match standalone 'Mai'")
        if let date = dateFromMai {
            let components = Calendar.current.dateComponents([.month], from: date)
            XCTAssertEqual(components.month, 5)
        }
    }

    // MARK: - Company Extraction Tests

    func testExtractCompanyWithKeywords() throws {
        let text = """
        Acme Corporation GmbH
        Musterstraße 123
        12345 Berlin
        """

        let company = engine.extractCompany(from: text)
        XCTAssertNotNil(company)
        XCTAssertTrue(try XCTUnwrap(company?.contains("Acme")))
    }

    func testExtractCompanyFirstLine() {
        let text = """
        My Company Name
        Some address
        Some city
        """

        let company = engine.extractCompany(from: text)
        // sanitizeCompanyName replaces spaces with underscores
        XCTAssertEqual(company, "My_Company_Name")
    }

    func testExtractCompanyWithLegalSuffix() throws {
        let text = """
        Some Random Text
        Another Line
        BigCorp AG
        More text here
        """

        let company = engine.extractCompany(from: text)
        XCTAssertNotNil(company)
        XCTAssertTrue(try XCTUnwrap(company?.contains("BigCorp")))
    }

    func testExtractCompanyWithLLC() throws {
        let text = """
        Random Header
        Tech Solutions LLC
        Address Line
        """

        let company = engine.extractCompany(from: text)
        XCTAssertNotNil(company)
        XCTAssertTrue(try XCTUnwrap(company?.contains("Tech")))
        XCTAssertTrue(try XCTUnwrap(company?.contains("LLC")))
    }

    func testExtractCompanyWithCorporation() throws {
        let text = """
        Some text
        Apple Corporation
        More text
        """

        let company = engine.extractCompany(from: text)
        XCTAssertNotNil(company)
        XCTAssertTrue(try XCTUnwrap(company?.contains("Apple")))
    }

    func testExtractCompanyEmptyText() {
        let company = engine.extractCompany(from: "")
        XCTAssertNil(company)
    }

    func testExtractCompanyOnlyWhitespace() {
        let company = engine.extractCompany(from: "   \n\n   ")
        XCTAssertNil(company)
    }

    func testExtractCompanyShortFirstLine() {
        // First line is too short (<=3 chars), no company keywords
        let text = """
        Ab
        Another line
        """

        let company = engine.extractCompany(from: text)
        // Should return nil as first line is too short and no keywords found
        XCTAssertNil(company)
    }
}
