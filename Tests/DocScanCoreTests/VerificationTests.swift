import XCTest
@testable import DocScanCore

final class VerificationTests: XCTestCase {
    // MARK: - CategorizationResult Tests

    func testCategorizationResultInitialization() {
        let result = CategorizationResult(
            isInvoice: true,
            confidence: "high",
            method: "VLM",
            reason: "Contains invoice keywords"
        )

        XCTAssertTrue(result.isInvoice)
        XCTAssertEqual(result.confidence, "high")
        XCTAssertEqual(result.method, "VLM")
        XCTAssertEqual(result.reason, "Contains invoice keywords")
    }

    func testCategorizationResultDefaultConfidence() {
        let result = CategorizationResult(
            isInvoice: false,
            method: "OCR"
        )

        XCTAssertFalse(result.isInvoice)
        XCTAssertEqual(result.confidence, "high") // default value
        XCTAssertEqual(result.method, "OCR")
        XCTAssertNil(result.reason)
    }

    // MARK: - CategorizationVerification Tests

    func testCategorizationVerificationBothAgreeInvoice() {
        let vlm = CategorizationResult(isInvoice: true, method: "VLM")
        let ocr = CategorizationResult(isInvoice: true, method: "OCR")

        let verification = CategorizationVerification(vlmResult: vlm, ocrResult: ocr)

        XCTAssertTrue(verification.bothAgree)
        XCTAssertEqual(verification.agreedIsInvoice, true)
    }

    func testCategorizationVerificationBothAgreeNotInvoice() {
        let vlm = CategorizationResult(isInvoice: false, method: "VLM")
        let ocr = CategorizationResult(isInvoice: false, method: "OCR")

        let verification = CategorizationVerification(vlmResult: vlm, ocrResult: ocr)

        XCTAssertTrue(verification.bothAgree)
        XCTAssertEqual(verification.agreedIsInvoice, false)
    }

    func testCategorizationVerificationConflict() {
        let vlm = CategorizationResult(isInvoice: true, method: "VLM")
        let ocr = CategorizationResult(isInvoice: false, method: "OCR")

        let verification = CategorizationVerification(vlmResult: vlm, ocrResult: ocr)

        XCTAssertFalse(verification.bothAgree)
        XCTAssertNil(verification.agreedIsInvoice)
    }

    func testCategorizationVerificationConflictReverse() {
        let vlm = CategorizationResult(isInvoice: false, method: "VLM")
        let ocr = CategorizationResult(isInvoice: true, method: "OCR")

        let verification = CategorizationVerification(vlmResult: vlm, ocrResult: ocr)

        XCTAssertFalse(verification.bothAgree)
        XCTAssertNil(verification.agreedIsInvoice)
    }

    // MARK: - ExtractionResult Tests

    func testExtractionResultInitialization() {
        let date = Date()
        let result = ExtractionResult(date: date, company: "Test Corp")

        XCTAssertEqual(result.date, date)
        XCTAssertEqual(result.company, "Test Corp")
    }

    func testExtractionResultNilValues() {
        let result = ExtractionResult(date: nil, company: nil)

        XCTAssertNil(result.date)
        XCTAssertNil(result.company)
    }

    func testExtractionResultPartialValues() {
        let date = Date()
        let result = ExtractionResult(date: date, company: nil)

        XCTAssertEqual(result.date, date)
        XCTAssertNil(result.company)
    }

    // MARK: - InvoiceData Tests

    func testInvoiceDataInitialization() {
        let date = Date()
        let invoiceData = InvoiceData(
            isInvoice: true,
            date: date,
            company: "Acme Corp"
        )

        XCTAssertTrue(invoiceData.isInvoice)
        XCTAssertEqual(invoiceData.date, date)
        XCTAssertEqual(invoiceData.company, "Acme Corp")
        XCTAssertNil(invoiceData.categorization)
    }

    func testInvoiceDataWithCategorization() {
        let date = Date()
        let vlm = CategorizationResult(isInvoice: true, method: "VLM")
        let ocr = CategorizationResult(isInvoice: true, method: "OCR")
        let categorization = CategorizationVerification(vlmResult: vlm, ocrResult: ocr)

        let invoiceData = InvoiceData(
            isInvoice: true,
            date: date,
            company: "Test Corp",
            categorization: categorization
        )

        XCTAssertTrue(invoiceData.isInvoice)
        XCTAssertEqual(invoiceData.date, date)
        XCTAssertEqual(invoiceData.company, "Test Corp")
        XCTAssertNotNil(invoiceData.categorization)
        XCTAssertTrue(invoiceData.categorization!.bothAgree)
    }

    func testInvoiceDataNotInvoice() {
        let invoiceData = InvoiceData(
            isInvoice: false,
            date: nil,
            company: nil
        )

        XCTAssertFalse(invoiceData.isInvoice)
        XCTAssertNil(invoiceData.date)
        XCTAssertNil(invoiceData.company)
    }
}
