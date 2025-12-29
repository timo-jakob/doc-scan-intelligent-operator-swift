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

    // MARK: - Display Label Tests

    func testDisplayLabelVLM() {
        let result = CategorizationResult(isInvoice: true, method: "VLM")
        XCTAssertEqual(result.displayLabel, "VLM (Vision Language Model)")
    }

    func testDisplayLabelPDF() {
        let result = CategorizationResult(isInvoice: true, method: "PDF")
        XCTAssertEqual(result.displayLabel, "PDF (Direct Text Extraction)")
    }

    func testDisplayLabelOCR() {
        let result = CategorizationResult(isInvoice: true, method: "OCR")
        XCTAssertEqual(result.displayLabel, "OCR (Vision Framework)")
    }

    func testDisplayLabelUnknownMethod() {
        let result = CategorizationResult(isInvoice: true, method: "CustomMethod")
        XCTAssertEqual(result.displayLabel, "CustomMethod")
    }

    func testShortDisplayLabelVLM() {
        let result = CategorizationResult(isInvoice: true, method: "VLM")
        XCTAssertEqual(result.shortDisplayLabel, "VLM")
    }

    func testShortDisplayLabelPDF() {
        let result = CategorizationResult(isInvoice: true, method: "PDF")
        XCTAssertEqual(result.shortDisplayLabel, "PDF text")
    }

    func testShortDisplayLabelOCR() {
        let result = CategorizationResult(isInvoice: true, method: "OCR")
        XCTAssertEqual(result.shortDisplayLabel, "Vision OCR")
    }

    func testShortDisplayLabelUnknownMethod() {
        let result = CategorizationResult(isInvoice: true, method: "CustomMethod")
        XCTAssertEqual(result.shortDisplayLabel, "CustomMethod")
    }

    func testDisplayLabelsWithDifferentInvoiceStatus() {
        // Verify labels work regardless of isInvoice value
        let invoiceResult = CategorizationResult(isInvoice: true, method: "PDF")
        let notInvoiceResult = CategorizationResult(isInvoice: false, method: "PDF")

        XCTAssertEqual(invoiceResult.displayLabel, notInvoiceResult.displayLabel)
        XCTAssertEqual(invoiceResult.shortDisplayLabel, notInvoiceResult.shortDisplayLabel)
    }

    // MARK: - Timeout and Error Display Label Tests

    func testDisplayLabelVLMTimeout() {
        let result = CategorizationResult(isInvoice: false, method: "VLM (timeout)")
        XCTAssertEqual(result.displayLabel, "VLM (Vision Language Model - Timeout)")
    }

    func testDisplayLabelVLMError() {
        let result = CategorizationResult(isInvoice: false, method: "VLM (error)")
        XCTAssertEqual(result.displayLabel, "VLM (Vision Language Model - Error)")
    }

    func testDisplayLabelOCRTimeout() {
        let result = CategorizationResult(isInvoice: false, method: "OCR (timeout)")
        XCTAssertEqual(result.displayLabel, "OCR (Vision Framework - Timeout)")
    }

    func testShortDisplayLabelVLMTimeout() {
        let result = CategorizationResult(isInvoice: false, method: "VLM (timeout)")
        XCTAssertEqual(result.shortDisplayLabel, "VLM (timeout)")
    }

    func testShortDisplayLabelVLMError() {
        let result = CategorizationResult(isInvoice: false, method: "VLM (error)")
        XCTAssertEqual(result.shortDisplayLabel, "VLM (error)")
    }

    func testShortDisplayLabelOCRTimeout() {
        let result = CategorizationResult(isInvoice: false, method: "OCR (timeout)")
        XCTAssertEqual(result.shortDisplayLabel, "OCR (timeout)")
    }

    func testDisplayLabelWithVariousVLMFormats() {
        // Test various VLM method formats that might appear
        let vlmOnly = CategorizationResult(isInvoice: true, method: "VLM")
        let vlmTimeout = CategorizationResult(isInvoice: false, method: "VLM (timeout)")
        let vlmError = CategorizationResult(isInvoice: false, method: "VLM (error)")

        XCTAssertTrue(vlmOnly.displayLabel.contains("Vision Language Model"))
        XCTAssertTrue(vlmTimeout.displayLabel.contains("Timeout"))
        XCTAssertTrue(vlmError.displayLabel.contains("Error"))
    }

    func testDisplayLabelWithVariousOCRFormats() {
        // Test various OCR method formats that might appear
        let ocrOnly = CategorizationResult(isInvoice: true, method: "OCR")
        let ocrTimeout = CategorizationResult(isInvoice: false, method: "OCR (timeout)")

        XCTAssertTrue(ocrOnly.displayLabel.contains("Vision Framework"))
        XCTAssertTrue(ocrTimeout.displayLabel.contains("Timeout"))
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
