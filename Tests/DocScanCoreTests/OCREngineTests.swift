import XCTest
import Vision
@testable import DocScanCore

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
        let (isInvoice1, confidence1, reason1) = engine.detectInvoiceKeywords(from: strongText)
        XCTAssertTrue(isInvoice1)
        XCTAssertEqual(confidence1, "high")
        XCTAssertNotNil(reason1)

        // Medium indicators
        let mediumText = "Rechnung für Dienstleistungen"
        let (isInvoice2, confidence2, _) = engine.detectInvoiceKeywords(from: mediumText)
        XCTAssertTrue(isInvoice2)
        XCTAssertEqual(confidence2, "medium")

        // No invoice keywords
        let noInvoiceText = "Just a regular document"
        let (isInvoice3, confidence3, _) = engine.detectInvoiceKeywords(from: noInvoiceText)
        XCTAssertFalse(isInvoice3)
        XCTAssertEqual(confidence3, "high") // High confidence it's NOT an invoice
    }

    // MARK: - Date Extraction Tests

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

    func testExtractDateColonSeparated() {
        // OCR sometimes reads dots as colons
        let text = "Datum:13:11:2025"
        let date = engine.extractDate(from: text)

        XCTAssertNotNil(date)
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month, .day], from: date!)
        XCTAssertEqual(components.year, 2025)
        XCTAssertEqual(components.month, 11)
        XCTAssertEqual(components.day, 13)
    }

    func testExtractDateGermanMonth() {
        let text = "Beitragsrechnung September 2022"
        let date = engine.extractDate(from: text)

        XCTAssertNotNil(date)
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month, .day], from: date!)
        XCTAssertEqual(components.year, 2022)
        XCTAssertEqual(components.month, 9)
        XCTAssertEqual(components.day, 1) // First of month for month-only dates
    }

    func testExtractDateGermanMonthAbbreviated() {
        let text = "Rechnung Okt 2023"
        let date = engine.extractDate(from: text)

        XCTAssertNotNil(date)
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month, .day], from: date!)
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
        // sanitizeCompanyName replaces spaces with underscores
        XCTAssertEqual(company, "My_Company_Name")
    }

    func testExtractCompanyWithLegalSuffix() {
        let text = """
        Some Random Text
        Another Line
        BigCorp AG
        More text here
        """

        let company = engine.extractCompany(from: text)
        XCTAssertNotNil(company)
        XCTAssertTrue(company!.contains("BigCorp"))
    }
}
