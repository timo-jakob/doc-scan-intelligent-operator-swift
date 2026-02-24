@testable import DocScanCore
import Vision
import XCTest

// MARK: - Static detectKeywords Tests

extension OCREngineTests {
    func testStaticDetectInvoiceKeywordsStrongIndicators() {
        let strongTexts = [
            "Rechnungsnummer: 12345",
            "Invoice Number: INV-2024-001",
            "Numéro de facture: 98765",
            "Número de factura: FAC-2024",
            "Rechnungsdatum: 15.12.2024",
            "Invoice Date: December 15, 2024",
        ]

        for text in strongTexts {
            let result = OCREngine.detectKeywords(for: .invoice, from: text)
            XCTAssertTrue(result.isMatch, "Should detect invoice in: \(text)")
            XCTAssertEqual(result.confidence, .high, "Should have high confidence for: \(text)")
        }
    }

    func testStaticDetectInvoiceKeywordsMediumIndicators() {
        let mediumTexts = [
            "This is a Rechnung",
            "Your Invoice is attached",
            "La facture",
            "La factura",
            "Quittung",
            "Receipt for your purchase",
        ]

        for text in mediumTexts {
            let result = OCREngine.detectKeywords(for: .invoice, from: text)
            XCTAssertTrue(result.isMatch, "Should detect invoice in: \(text)")
            XCTAssertEqual(result.confidence, .medium, "Should have medium confidence for: \(text)")
        }
    }

    func testStaticDetectInvoiceKeywordsNoInvoice() {
        let nonInvoiceTexts = [
            "Hello world",
            "This is a regular document",
            "Meeting notes for December",
            "Project plan and timeline",
        ]

        for text in nonInvoiceTexts {
            let result = OCREngine.detectKeywords(for: .invoice, from: text)
            XCTAssertFalse(result.isMatch, "Should not detect invoice in: \(text)")
            XCTAssertEqual(
                result.confidence, .high,
                "Should have high confidence it's NOT an invoice for: \(text)"
            )
            XCTAssertEqual(result.reason, "No invoice keywords found")
        }
    }

    func testDetectInvoiceKeywordsCaseInsensitive() {
        let testCases = [
            "RECHNUNG",
            "rechnung",
            "Rechnung",
            "INVOICE",
            "Invoice",
            "invoice",
        ]

        for text in testCases {
            let result = OCREngine.detectKeywords(for: .invoice, from: text)
            XCTAssertTrue(result.isMatch, "Should detect invoice case-insensitively in: \(text)")
        }
    }

    // MARK: - Additional Date Extraction Tests

    func testExtractDateUSFormat() throws {
        // US format MM/dd/yyyy
        let text = "Date: 12/22/2024"
        let date = engine.extractDate(from: text)

        XCTAssertNotNil(date)
        let calendar = Calendar.current
        let components = try calendar.dateComponents([.year, .month, .day], from: XCTUnwrap(date))
        XCTAssertEqual(components.year, 2024)
        XCTAssertEqual(components.month, 12)
        XCTAssertEqual(components.day, 22)
    }

    func testExtractDateSlashSeparated() throws {
        let text = "Datum: 22/12/2024"
        let date = engine.extractDate(from: text)

        XCTAssertNotNil(date)
        let calendar = Calendar.current
        let components = try calendar.dateComponents([.year, .month, .day], from: XCTUnwrap(date))
        XCTAssertEqual(components.year, 2024)
        XCTAssertEqual(components.month, 12)
        XCTAssertEqual(components.day, 22)
    }

    // MARK: - Instance vs Static Method Tests

    func testInstanceMethodDelegationToStatic() {
        let text = "Rechnungsnummer: 12345"

        // Both should return the same results
        let instanceResult = engine.detectKeywords(for: .invoice, from: text)
        let staticResult = OCREngine.detectKeywords(for: .invoice, from: text)

        XCTAssertEqual(instanceResult.isMatch, staticResult.isMatch)
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
        XCTAssertTrue(engine.detectKeywords(for: .invoice, from: "Rechnung").isMatch)
        XCTAssertTrue(engine.detectKeywords(for: .invoice, from: "Invoice").isMatch)
        XCTAssertTrue(engine.detectKeywords(for: .invoice, from: "Rechnungsnummer: 12345").isMatch)
        XCTAssertFalse(engine.detectKeywords(for: .invoice, from: "Hello World").isMatch)
        XCTAssertFalse(engine.detectKeywords(for: .invoice, from: "").isMatch)
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
            ("Another OHG\nMunich", "OHG"),
        ]

        for (text, expectedContains) in testCases {
            let company = engine.extractCompany(from: text)
            XCTAssertNotNil(company, "Should extract company from: \(text)")
            if let company {
                XCTAssertTrue(
                    company.contains(expectedContains),
                    "Company '\(company)' should contain '\(expectedContains)'"
                )
            }
        }
    }

    // MARK: - Multiple Keywords in Same Text

    func testDetectInvoiceMultipleKeywords() throws {
        let text = """
        Rechnung
        Rechnungsnummer: 12345
        Invoice Date: 2024-12-15
        """

        let result = engine.detectKeywords(for: .invoice, from: text)

        XCTAssertTrue(result.isMatch)
        XCTAssertEqual(result.confidence, .high) // Strong indicators present
        XCTAssertNotNil(result.reason)
        // Should contain multiple keywords in reason
        let reason = try XCTUnwrap(result.reason)
        XCTAssertTrue(reason.contains("rechnungsnummer") || reason.contains("invoice date"))
    }
}
