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

    func testExtractCompanyWithLLC() {
        let text = """
        Random Header
        Tech Solutions LLC
        Address Line
        """

        let company = engine.extractCompany(from: text)
        XCTAssertNotNil(company)
        XCTAssertTrue(company!.contains("Tech"))
        XCTAssertTrue(company!.contains("LLC"))
    }

    func testExtractCompanyWithCorporation() {
        let text = """
        Some text
        Apple Corporation
        More text
        """

        let company = engine.extractCompany(from: text)
        XCTAssertNotNil(company)
        XCTAssertTrue(company!.contains("Apple"))
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

    // MARK: - Static detectInvoiceKeywords Tests

    func testStaticDetectInvoiceKeywordsStrongIndicators() {
        let strongTexts = [
            "Rechnungsnummer: 12345",
            "Invoice Number: INV-2024-001",
            "Numéro de facture: 98765",
            "Número de factura: FAC-2024",
            "Rechnungsdatum: 15.12.2024",
            "Invoice Date: December 15, 2024"
        ]

        for text in strongTexts {
            let (isInvoice, confidence, _) = OCREngine.detectInvoiceKeywords(from: text)
            XCTAssertTrue(isInvoice, "Should detect invoice in: \(text)")
            XCTAssertEqual(confidence, "high", "Should have high confidence for: \(text)")
        }
    }

    func testStaticDetectInvoiceKeywordsMediumIndicators() {
        let mediumTexts = [
            "This is a Rechnung",
            "Your Invoice is attached",
            "La facture",
            "La factura",
            "Quittung",
            "Receipt for your purchase"
        ]

        for text in mediumTexts {
            let (isInvoice, confidence, _) = OCREngine.detectInvoiceKeywords(from: text)
            XCTAssertTrue(isInvoice, "Should detect invoice in: \(text)")
            XCTAssertEqual(confidence, "medium", "Should have medium confidence for: \(text)")
        }
    }

    func testStaticDetectInvoiceKeywordsNoInvoice() {
        let nonInvoiceTexts = [
            "Hello world",
            "This is a regular document",
            "Meeting notes for December",
            "Project plan and timeline"
        ]

        for text in nonInvoiceTexts {
            let (isInvoice, confidence, reason) = OCREngine.detectInvoiceKeywords(from: text)
            XCTAssertFalse(isInvoice, "Should not detect invoice in: \(text)")
            XCTAssertEqual(confidence, "high", "Should have high confidence it's NOT an invoice for: \(text)")
            XCTAssertEqual(reason, "No invoice keywords found")
        }
    }

    func testDetectInvoiceKeywordsCaseInsensitive() {
        let testCases = [
            "RECHNUNG",
            "rechnung",
            "Rechnung",
            "INVOICE",
            "Invoice",
            "invoice"
        ]

        for text in testCases {
            let (isInvoice, _, _) = OCREngine.detectInvoiceKeywords(from: text)
            XCTAssertTrue(isInvoice, "Should detect invoice case-insensitively in: \(text)")
        }
    }

    // MARK: - Additional Date Extraction Tests

    func testExtractDateUSFormat() {
        // US format MM/dd/yyyy
        let text = "Date: 12/22/2024"
        let date = engine.extractDate(from: text)

        XCTAssertNotNil(date)
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month, .day], from: date!)
        XCTAssertEqual(components.year, 2024)
        XCTAssertEqual(components.month, 12)
        XCTAssertEqual(components.day, 22)
    }

    func testExtractDateSlashSeparated() {
        let text = "Datum: 22/12/2024"
        let date = engine.extractDate(from: text)

        XCTAssertNotNil(date)
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month, .day], from: date!)
        XCTAssertEqual(components.year, 2024)
        XCTAssertEqual(components.month, 12)
        XCTAssertEqual(components.day, 22)
    }

    // MARK: - Instance vs Static Method Tests

    func testInstanceMethodDelegationToStatic() {
        let text = "Rechnungsnummer: 12345"

        // Both should return the same results
        let instanceResult = engine.detectInvoiceKeywords(from: text)
        let staticResult = OCREngine.detectInvoiceKeywords(from: text)

        XCTAssertEqual(instanceResult.isInvoice, staticResult.isInvoice)
        XCTAssertEqual(instanceResult.confidence, staticResult.confidence)
        XCTAssertEqual(instanceResult.reason, staticResult.reason)
    }

    // MARK: - extractTextFromObservations Additional Tests

    func testExtractTextFromObservationsReturnsJoinedString() {
        // The method joins observations with newlines
        // Since we can't easily create VNRecognizedTextObservation in tests,
        // we just verify empty array behavior
        let result = OCREngine.extractTextFromObservations([])
        XCTAssertTrue(result.isEmpty)
    }

    // MARK: - Detect Invoice Simple Tests

    func testDetectInvoiceSimple() {
        XCTAssertTrue(engine.detectInvoice(from: "Rechnung"))
        XCTAssertTrue(engine.detectInvoice(from: "Invoice"))
        XCTAssertTrue(engine.detectInvoice(from: "Rechnungsnummer: 12345"))
        XCTAssertFalse(engine.detectInvoice(from: "Hello World"))
        XCTAssertFalse(engine.detectInvoice(from: ""))
    }

    // MARK: - Company Extraction with Various Legal Suffixes

    func testExtractCompanyWithVariousLegalSuffixes() {
        let testCases: [(text: String, expectedContains: String)] = [
            ("Company Inc\nAddress", "Inc"),
            ("Business Ltd\nCity", "Ltd"),
            ("Startup Corp\nState", "Corp"),
            ("French SARL\nParis", "SARL"),
            ("Spanish S.A.\nMadrid", "S.A."),
            ("German KG\nBerlin", "KG"),
            ("Another OHG\nMunich", "OHG")
        ]

        for (text, expectedContains) in testCases {
            let company = engine.extractCompany(from: text)
            XCTAssertNotNil(company, "Should extract company from: \(text)")
            if let company = company {
                XCTAssertTrue(company.contains(expectedContains), "Company '\(company)' should contain '\(expectedContains)'")
            }
        }
    }

    // MARK: - Multiple Keywords in Same Text

    func testDetectInvoiceMultipleKeywords() {
        let text = """
        Rechnung
        Rechnungsnummer: 12345
        Invoice Date: 2024-12-15
        """

        let (isInvoice, confidence, reason) = engine.detectInvoiceKeywords(from: text)

        XCTAssertTrue(isInvoice)
        XCTAssertEqual(confidence, "high") // Strong indicators present
        XCTAssertNotNil(reason)
        // Should contain multiple keywords in reason
        XCTAssertTrue(reason!.contains("rechnungsnummer") || reason!.contains("invoice date"))
    }

    // MARK: - Generic detectKeywords Tests (Multi-Document Type Support)

    func testDetectKeywordsInvoiceStrongIndicators() {
        let text = "Rechnungsnummer: 12345\nInvoice Date: 2024-12-15"

        let result = OCREngine.detectKeywords(for: .invoice, from: text)

        XCTAssertTrue(result.isMatch)
        XCTAssertEqual(result.confidence, "high")
        XCTAssertNotNil(result.reason)
    }

    func testDetectKeywordsInvoiceMediumIndicators() {
        let text = "This is a Rechnung for services"

        let result = OCREngine.detectKeywords(for: .invoice, from: text)

        XCTAssertTrue(result.isMatch)
        XCTAssertEqual(result.confidence, "medium")
    }

    func testDetectKeywordsInvoiceNoMatch() {
        let text = "Hello world"

        let result = OCREngine.detectKeywords(for: .invoice, from: text)

        XCTAssertFalse(result.isMatch)
        XCTAssertEqual(result.confidence, "high")
        XCTAssertEqual(result.reason, "No invoice keywords found")
    }

    func testDetectKeywordsPrescriptionStrongIndicators() {
        let strongTexts = [
            "Rezept Nr. 12345",
            "Verordnung für Patient",
            "Prescription #123",
            "PZN: 1234567",
            "Kassenärztliche Verordnung"
        ]

        for text in strongTexts {
            let result = OCREngine.detectKeywords(for: .prescription, from: text)
            XCTAssertTrue(result.isMatch, "Should detect prescription in: \(text)")
            XCTAssertEqual(result.confidence, "high", "Should have high confidence for: \(text)")
        }
    }

    func testDetectKeywordsPrescriptionMediumIndicators() {
        let mediumTexts = [
            "Dr. med. Hans Müller - Arzt",
            "Praxis für Allgemeinmedizin",
            "Medikament: Ibuprofen 400mg",
            "Apotheke zur Rose"
        ]

        for text in mediumTexts {
            let result = OCREngine.detectKeywords(for: .prescription, from: text)
            XCTAssertTrue(result.isMatch, "Should detect prescription in: \(text)")
            XCTAssertEqual(result.confidence, "medium", "Should have medium confidence for: \(text)")
        }
    }

    func testDetectKeywordsPrescriptionNoMatch() {
        let text = "This is just a regular business document"

        let result = OCREngine.detectKeywords(for: .prescription, from: text)

        XCTAssertFalse(result.isMatch)
        XCTAssertEqual(result.confidence, "high")
        XCTAssertEqual(result.reason, "No prescription keywords found")
    }

    func testDetectKeywordsPrescriptionCaseInsensitive() {
        let testCases = [
            "REZEPT",
            "rezept",
            "Rezept",
            "VERORDNUNG",
            "Verordnung",
            "verordnung"
        ]

        for text in testCases {
            let result = OCREngine.detectKeywords(for: .prescription, from: text)
            XCTAssertTrue(result.isMatch, "Should detect prescription case-insensitively in: \(text)")
        }
    }

    func testDetectKeywordsInstanceMethodDelegatesToStatic() {
        let text = "Rezept Nr. 12345"

        let instanceResult = engine.detectKeywords(for: .prescription, from: text)
        let staticResult = OCREngine.detectKeywords(for: .prescription, from: text)

        XCTAssertEqual(instanceResult.isMatch, staticResult.isMatch)
        XCTAssertEqual(instanceResult.confidence, staticResult.confidence)
        XCTAssertEqual(instanceResult.reason, staticResult.reason)
    }

    func testDetectKeywordsPrescriptionRealWorldExamples() {
        let examples: [(text: String, shouldMatch: Bool)] = [
            ("Dr. med. Gesine Kaiser\nPraxis für Allgemeinmedizin\nRezept", true),
            ("Kassenrezept\nPZN 04356752\nIbuprofen 400mg", true),
            ("Privatrezept\nVerordnung für Max Mustermann", true),
            ("Rechnung für Arztbesuch\nBetrag: 50 EUR", true), // Contains "arzt"
            ("Einkaufsliste:\n- Milch\n- Brot", false)
        ]

        for (text, shouldMatch) in examples {
            let result = OCREngine.detectKeywords(for: .prescription, from: text)
            XCTAssertEqual(result.isMatch, shouldMatch, "Unexpected result for: \(text.prefix(50))...")
        }
    }

    func testDetectKeywordsAllDocumentTypes() {
        // Test that each document type has distinct keywords
        let invoiceText = "Rechnungsnummer: 12345"
        let prescriptionText = "Rezept Nr. 12345"

        let invoiceAsInvoice = OCREngine.detectKeywords(for: .invoice, from: invoiceText)
        let invoiceAsPrescription = OCREngine.detectKeywords(for: .prescription, from: invoiceText)
        let prescriptionAsInvoice = OCREngine.detectKeywords(for: .invoice, from: prescriptionText)
        let prescriptionAsPrescription = OCREngine.detectKeywords(for: .prescription, from: prescriptionText)

        // Invoice text should match invoice type, not prescription
        XCTAssertTrue(invoiceAsInvoice.isMatch)
        XCTAssertFalse(invoiceAsPrescription.isMatch)

        // Prescription text should match prescription type, not invoice
        XCTAssertFalse(prescriptionAsInvoice.isMatch)
        XCTAssertTrue(prescriptionAsPrescription.isMatch)
    }
}
