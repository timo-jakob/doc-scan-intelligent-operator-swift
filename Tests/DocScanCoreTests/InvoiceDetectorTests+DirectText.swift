import AppKit
@testable import DocScanCore
import PDFKit
import XCTest

// MARK: - Direct Text Categorization Tests

extension InvoiceDetectorTests {
    func testCategorizeWithDirectTextInvoice() {
        let invoiceText = """
        DB Fernverkehr AG
        Rechnung
        Rechnungsnummer: 2025018156792
        Datum: 27.06.2025
        Betrag: 81,90 \u{20AC}
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
}
