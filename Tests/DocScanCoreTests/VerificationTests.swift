import XCTest
@testable import DocScanCore

final class VerificationTests: XCTestCase {
    func testExtractionResultInitialization() {
        let result = ExtractionResult(
            isInvoice: true,
            date: Date(),
            company: "Test Corp",
            method: "VLM"
        )

        XCTAssertTrue(result.isInvoice)
        XCTAssertNotNil(result.date)
        XCTAssertEqual(result.company, "Test Corp")
        XCTAssertEqual(result.method, "VLM")
    }

    func testVerificationResultNoConflict() {
        let date = Date()
        let vml = ExtractionResult(
            isInvoice: true,
            date: date,
            company: "Acme Corp",
            method: "VLM"
        )
        let ocr = ExtractionResult(
            isInvoice: true,
            date: date,
            company: "Acme Corp",
            method: "OCR"
        )

        let verification = VerificationResult(vmlResult: vml, ocrResult: ocr)

        XCTAssertFalse(verification.hasConflict)
        XCTAssertTrue(verification.conflicts.isEmpty)
        XCTAssertNotNil(verification.agreedResult)
    }

    func testVerificationResultInvoiceConflict() {
        let vml = ExtractionResult(
            isInvoice: true,
            date: Date(),
            company: "Acme Corp",
            method: "VLM"
        )
        let ocr = ExtractionResult(
            isInvoice: false,
            date: Date(),
            company: "Acme Corp",
            method: "OCR"
        )

        let verification = VerificationResult(vmlResult: vml, ocrResult: ocr)

        XCTAssertTrue(verification.hasConflict)
        XCTAssertTrue(verification.conflicts.contains("Invoice detection"))
        XCTAssertNil(verification.agreedResult)
    }

    func testVerificationResultDateConflict() {
        let date1 = Date()
        let date2 = Date().addingTimeInterval(86400) // +1 day

        let vml = ExtractionResult(
            isInvoice: true,
            date: date1,
            company: "Acme Corp",
            method: "VLM"
        )
        let ocr = ExtractionResult(
            isInvoice: true,
            date: date2,
            company: "Acme Corp",
            method: "OCR"
        )

        let verification = VerificationResult(vmlResult: vml, ocrResult: ocr)

        XCTAssertTrue(verification.hasConflict)
        XCTAssertTrue(verification.conflicts.contains("Date"))
        XCTAssertNil(verification.agreedResult)
    }

    func testVerificationResultCompanyConflict() {
        let date = Date()
        let vml = ExtractionResult(
            isInvoice: true,
            date: date,
            company: "Acme Corp",
            method: "VLM"
        )
        let ocr = ExtractionResult(
            isInvoice: true,
            date: date,
            company: "Different Corp",
            method: "OCR"
        )

        let verification = VerificationResult(vmlResult: vml, ocrResult: ocr)

        XCTAssertTrue(verification.hasConflict)
        XCTAssertTrue(verification.conflicts.contains("Company name"))
        XCTAssertNil(verification.agreedResult)
    }

    func testVerificationResultMultipleConflicts() {
        let vml = ExtractionResult(
            isInvoice: true,
            date: Date(),
            company: "Acme Corp",
            method: "VLM"
        )
        let ocr = ExtractionResult(
            isInvoice: false,
            date: Date().addingTimeInterval(86400),
            company: "Different Corp",
            method: "OCR"
        )

        let verification = VerificationResult(vmlResult: vml, ocrResult: ocr)

        XCTAssertTrue(verification.hasConflict)
        XCTAssertEqual(verification.conflicts.count, 3)
        XCTAssertTrue(verification.conflicts.contains("Invoice detection"))
        XCTAssertTrue(verification.conflicts.contains("Date"))
        XCTAssertTrue(verification.conflicts.contains("Company name"))
        XCTAssertNil(verification.agreedResult)
    }

    func testInvoiceDataFromExtractionResult() {
        let date = Date()
        let result = ExtractionResult(
            isInvoice: true,
            date: date,
            company: "Test Corp",
            method: "VLM"
        )

        let invoiceData = InvoiceData(from: result)

        XCTAssertTrue(invoiceData.isInvoice)
        XCTAssertEqual(invoiceData.date, date)
        XCTAssertEqual(invoiceData.company, "Test Corp")
    }
}
