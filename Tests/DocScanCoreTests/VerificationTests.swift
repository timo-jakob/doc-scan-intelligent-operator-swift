@testable import DocScanCore
import XCTest

final class VerificationTests: XCTestCase {
    // MARK: - CategorizationResult Tests

    func testCategorizationResultInitialization() {
        let result = CategorizationResult(
            isMatch: true,
            confidence: .high,
            method: .vlm,
            reason: "Contains invoice keywords"
        )

        XCTAssertTrue(result.isMatch)
        XCTAssertEqual(result.confidence, .high)
        XCTAssertEqual(result.method, .vlm)
        XCTAssertEqual(result.reason, "Contains invoice keywords")
    }

    func testCategorizationResultDefaultConfidence() {
        let result = CategorizationResult(
            isMatch: false,
            method: .ocr
        )

        XCTAssertFalse(result.isMatch)
        XCTAssertEqual(result.confidence, .high) // default value
        XCTAssertEqual(result.method, .ocr)
        XCTAssertNil(result.reason)
    }

    // MARK: - Display Label Tests

    func testDisplayLabelVLM() {
        let result = CategorizationResult(isMatch: true, method: .vlm)
        XCTAssertEqual(result.displayLabel, "VLM (Vision Language Model)")
    }

    func testDisplayLabelPDF() {
        let result = CategorizationResult(isMatch: true, method: .pdf)
        XCTAssertEqual(result.displayLabel, "PDF (Direct Text Extraction)")
    }

    func testDisplayLabelOCR() {
        let result = CategorizationResult(isMatch: true, method: .ocr)
        XCTAssertEqual(result.displayLabel, "OCR (Vision Framework)")
    }

    func testShortDisplayLabelVLM() {
        let result = CategorizationResult(isMatch: true, method: .vlm)
        XCTAssertEqual(result.shortDisplayLabel, "VLM")
    }

    func testShortDisplayLabelPDF() {
        let result = CategorizationResult(isMatch: true, method: .pdf)
        XCTAssertEqual(result.shortDisplayLabel, "PDF text")
    }

    func testShortDisplayLabelOCR() {
        let result = CategorizationResult(isMatch: true, method: .ocr)
        XCTAssertEqual(result.shortDisplayLabel, "Vision OCR")
    }

    func testDisplayLabelsWithDifferentMatchStatus() {
        // Verify labels work regardless of isMatch value
        let matchResult = CategorizationResult(isMatch: true, method: .pdf)
        let notMatchResult = CategorizationResult(isMatch: false, method: .pdf)

        XCTAssertEqual(matchResult.displayLabel, notMatchResult.displayLabel)
        XCTAssertEqual(matchResult.shortDisplayLabel, notMatchResult.shortDisplayLabel)
    }

    // MARK: - Timeout and Error Display Label Tests

    func testDisplayLabelVLMTimeout() {
        let result = CategorizationResult(isMatch: false, method: .vlmTimeout)
        XCTAssertEqual(result.displayLabel, "VLM (Vision Language Model - Timeout)")
    }

    func testDisplayLabelVLMError() {
        let result = CategorizationResult(isMatch: false, method: .vlmError)
        XCTAssertEqual(result.displayLabel, "VLM (Vision Language Model - Error)")
    }

    func testDisplayLabelOCRTimeout() {
        let result = CategorizationResult(isMatch: false, method: .ocrTimeout)
        XCTAssertEqual(result.displayLabel, "OCR (Vision Framework - Timeout)")
    }

    func testShortDisplayLabelVLMTimeout() {
        let result = CategorizationResult(isMatch: false, method: .vlmTimeout)
        XCTAssertEqual(result.shortDisplayLabel, "VLM (timeout)")
    }

    func testShortDisplayLabelVLMError() {
        let result = CategorizationResult(isMatch: false, method: .vlmError)
        XCTAssertEqual(result.shortDisplayLabel, "VLM (error)")
    }

    func testShortDisplayLabelOCRTimeout() {
        let result = CategorizationResult(isMatch: false, method: .ocrTimeout)
        XCTAssertEqual(result.shortDisplayLabel, "OCR (timeout)")
    }

    func testDisplayLabelWithVariousVLMFormats() {
        // Test various VLM method formats that might appear
        let vlmOnly = CategorizationResult(isMatch: true, method: .vlm)
        let vlmTimeout = CategorizationResult(isMatch: false, method: .vlmTimeout)
        let vlmError = CategorizationResult(isMatch: false, method: .vlmError)

        XCTAssertTrue(vlmOnly.displayLabel.contains("Vision Language Model"))
        XCTAssertTrue(vlmTimeout.displayLabel.contains("Timeout"))
        XCTAssertTrue(vlmError.displayLabel.contains("Error"))
    }

    func testDisplayLabelWithVariousOCRFormats() {
        // Test various OCR method formats that might appear
        let ocrOnly = CategorizationResult(isMatch: true, method: .ocr)
        let ocrTimeout = CategorizationResult(isMatch: false, method: .ocrTimeout)

        XCTAssertTrue(ocrOnly.displayLabel.contains("Vision Framework"))
        XCTAssertTrue(ocrTimeout.displayLabel.contains("Timeout"))
    }

    // MARK: - Additional Display Label Edge Cases

    func testDisplayLabelPDFDoesNotContainTimeout() {
        // PDF method doesn't have timeout variants in the codebase
        let pdf = CategorizationResult(isMatch: true, method: .pdf)
        XCTAssertEqual(pdf.displayLabel, "PDF (Direct Text Extraction)")
        XCTAssertFalse(pdf.displayLabel.contains("Timeout"))
    }

    func testShortDisplayLabelPDFDoesNotContainTimeout() {
        let pdf = CategorizationResult(isMatch: true, method: .pdf)
        XCTAssertEqual(pdf.shortDisplayLabel, "PDF text")
    }

    func testDisplayLabelVLMWithErrorSubstring() {
        // Test that error detection works with different casing/formats
        let vlmError = CategorizationResult(isMatch: false, method: .vlmError)
        XCTAssertTrue(vlmError.displayLabel.hasPrefix("VLM"))
        XCTAssertTrue(vlmError.displayLabel.contains("Error"))
    }

    func testShortDisplayLabelVLMWithErrorSubstring() {
        let vlmError = CategorizationResult(isMatch: false, method: .vlmError)
        XCTAssertTrue(vlmError.shortDisplayLabel.hasPrefix("VLM"))
        XCTAssertTrue(vlmError.shortDisplayLabel.contains("error"))
    }

    func testDisplayLabelOCRWithTimeoutSubstring() {
        let ocrTimeout = CategorizationResult(isMatch: false, method: .ocrTimeout)
        XCTAssertTrue(ocrTimeout.displayLabel.hasPrefix("OCR"))
        XCTAssertTrue(ocrTimeout.displayLabel.contains("Timeout"))
    }

    func testShortDisplayLabelOCRWithTimeoutSubstring() {
        let ocrTimeout = CategorizationResult(isMatch: false, method: .ocrTimeout)
        XCTAssertTrue(ocrTimeout.shortDisplayLabel.hasPrefix("OCR"))
        XCTAssertTrue(ocrTimeout.shortDisplayLabel.contains("timeout"))
    }

    func testDisplayLabelVLMWithTimeoutSubstring() {
        let vlmTimeout = CategorizationResult(isMatch: false, method: .vlmTimeout)
        XCTAssertTrue(vlmTimeout.displayLabel.hasPrefix("VLM"))
        XCTAssertTrue(vlmTimeout.displayLabel.contains("Timeout"))
    }

    func testShortDisplayLabelVLMWithTimeoutSubstring() {
        let vlmTimeout = CategorizationResult(isMatch: false, method: .vlmTimeout)
        XCTAssertTrue(vlmTimeout.shortDisplayLabel.hasPrefix("VLM"))
        XCTAssertTrue(vlmTimeout.shortDisplayLabel.contains("timeout"))
    }

    func testAllMethodTypesHaveDistinctLabels() {
        let vlm = CategorizationResult(isMatch: true, method: .vlm)
        let pdf = CategorizationResult(isMatch: true, method: .pdf)
        let ocr = CategorizationResult(isMatch: true, method: .ocr)

        // All display labels should be different
        XCTAssertNotEqual(vlm.displayLabel, pdf.displayLabel)
        XCTAssertNotEqual(vlm.displayLabel, ocr.displayLabel)
        XCTAssertNotEqual(pdf.displayLabel, ocr.displayLabel)

        // All short labels should be different
        XCTAssertNotEqual(vlm.shortDisplayLabel, pdf.shortDisplayLabel)
        XCTAssertNotEqual(vlm.shortDisplayLabel, ocr.shortDisplayLabel)
        XCTAssertNotEqual(pdf.shortDisplayLabel, ocr.shortDisplayLabel)
    }

    // MARK: - isTimedOut Tests

    func testIsTimedOutFalseForNormalVLM() {
        let result = CategorizationResult(isMatch: true, method: .vlm)
        XCTAssertFalse(result.isTimedOut)
    }

    func testIsTimedOutFalseForNormalOCR() {
        let result = CategorizationResult(isMatch: true, method: .ocr)
        XCTAssertFalse(result.isTimedOut)
    }

    func testIsTimedOutFalseForPDF() {
        let result = CategorizationResult(isMatch: true, method: .pdf)
        XCTAssertFalse(result.isTimedOut)
    }

    func testIsTimedOutFalseForVLMError() {
        let result = CategorizationResult(isMatch: false, method: .vlmError)
        XCTAssertFalse(result.isTimedOut)
    }

    func testIsTimedOutTrueForVLMTimeout() {
        let result = CategorizationResult(isMatch: false, confidence: .low, method: .vlmTimeout)
        XCTAssertTrue(result.isTimedOut)
    }

    func testIsTimedOutTrueForOCRTimeout() {
        let result = CategorizationResult(isMatch: false, confidence: .low, method: .ocrTimeout)
        XCTAssertTrue(result.isTimedOut)
    }

    // MARK: - CategorizationVerification Tests

    func testCategorizationVerificationBothAgreeMatch() {
        let vlm = CategorizationResult(isMatch: true, method: .vlm)
        let ocr = CategorizationResult(isMatch: true, method: .ocr)

        let verification = CategorizationVerification(vlmResult: vlm, ocrResult: ocr)

        XCTAssertTrue(verification.bothAgree)
        XCTAssertEqual(verification.agreedIsMatch, true)
    }

    func testCategorizationVerificationBothAgreeNotMatch() {
        let vlm = CategorizationResult(isMatch: false, method: .vlm)
        let ocr = CategorizationResult(isMatch: false, method: .ocr)

        let verification = CategorizationVerification(vlmResult: vlm, ocrResult: ocr)

        XCTAssertTrue(verification.bothAgree)
        XCTAssertEqual(verification.agreedIsMatch, false)
    }

    func testCategorizationVerificationConflict() {
        let vlm = CategorizationResult(isMatch: true, method: .vlm)
        let ocr = CategorizationResult(isMatch: false, method: .ocr)

        let verification = CategorizationVerification(vlmResult: vlm, ocrResult: ocr)

        XCTAssertFalse(verification.bothAgree)
        XCTAssertNil(verification.agreedIsMatch)
    }

    func testCategorizationVerificationConflictReverse() {
        let vlm = CategorizationResult(isMatch: false, method: .vlm)
        let ocr = CategorizationResult(isMatch: true, method: .ocr)

        let verification = CategorizationVerification(vlmResult: vlm, ocrResult: ocr)

        XCTAssertFalse(verification.bothAgree)
        XCTAssertNil(verification.agreedIsMatch)
    }
}

// MARK: - ExtractionResult Tests

extension VerificationTests {
    func testExtractionResultInitialization() {
        let date = Date()
        let result = ExtractionResult(date: date, secondaryField: "Test Corp")

        XCTAssertEqual(result.date, date)
        XCTAssertEqual(result.secondaryField, "Test Corp")
    }

    func testExtractionResultNilValues() {
        let result = ExtractionResult(date: nil, secondaryField: nil)

        XCTAssertNil(result.date)
        XCTAssertNil(result.secondaryField)
    }

    func testExtractionResultPartialValues() {
        let date = Date()
        let result = ExtractionResult(date: date, secondaryField: nil)

        XCTAssertEqual(result.date, date)
        XCTAssertNil(result.secondaryField)
    }

    // MARK: - DocumentData Tests

    func testDocumentDataInitialization() {
        let date = Date()
        let documentData = DocumentData(
            documentType: .invoice,
            isMatch: true,
            date: date,
            secondaryField: "Acme Corp"
        )

        XCTAssertTrue(documentData.isMatch)
        XCTAssertEqual(documentData.date, date)
        XCTAssertEqual(documentData.secondaryField, "Acme Corp")
        XCTAssertNil(documentData.categorization)
    }

    func testDocumentDataWithCategorization() throws {
        let date = Date()
        let vlm = CategorizationResult(isMatch: true, method: .vlm)
        let ocr = CategorizationResult(isMatch: true, method: .ocr)
        let categorization = CategorizationVerification(vlmResult: vlm, ocrResult: ocr)

        let documentData = DocumentData(
            documentType: .invoice,
            isMatch: true,
            date: date,
            secondaryField: "Test Corp",
            categorization: categorization
        )

        XCTAssertTrue(documentData.isMatch)
        XCTAssertEqual(documentData.date, date)
        XCTAssertEqual(documentData.secondaryField, "Test Corp")
        XCTAssertNotNil(documentData.categorization)
        XCTAssertTrue(try XCTUnwrap(documentData.categorization?.bothAgree))
    }

    func testDocumentDataNotMatch() {
        let documentData = DocumentData(
            documentType: .invoice,
            isMatch: false,
            date: nil,
            secondaryField: nil
        )

        XCTAssertFalse(documentData.isMatch)
        XCTAssertNil(documentData.date)
        XCTAssertNil(documentData.secondaryField)
    }
}
