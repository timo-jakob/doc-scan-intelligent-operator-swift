@testable import DocScanCore
import Vision
import XCTest

// MARK: - Generic detectKeywords Tests (Multi-Document Type Support)

final class OCREngineKeywordsTests: XCTestCase {
    var engine: OCREngine!
    var config: Configuration!

    override func setUp() {
        super.setUp()
        config = Configuration.defaultConfiguration
        engine = OCREngine(config: config)
    }

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
            "Kassenärztliche Verordnung",
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
            "Apotheke zur Rose",
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
            "verordnung",
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
            ("Einkaufsliste:\n- Milch\n- Brot", false),
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
