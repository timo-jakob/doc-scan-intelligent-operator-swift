import XCTest
@testable import DocScanCore

final class ErrorsTests: XCTestCase {

    // MARK: - TimeoutError Tests

    func testTimeoutErrorDescription() {
        let error = TimeoutError()
        XCTAssertEqual(error.errorDescription, "Operation timed out")
    }

    func testTimeoutErrorLocalizedDescription() {
        let error = TimeoutError()
        XCTAssertEqual(error.localizedDescription, "Operation timed out")
    }

    // MARK: - DocScanError Tests

    func testInvalidPDFErrorDescription() {
        let error = DocScanError.invalidPDF("corrupted file")
        XCTAssertEqual(error.errorDescription, "Invalid PDF: corrupted file")
    }

    func testPdfConversionFailedErrorDescription() {
        let error = DocScanError.pdfConversionFailed("unable to render")
        XCTAssertEqual(error.errorDescription, "Failed to convert PDF: unable to render")
    }

    func testModelLoadFailedErrorDescription() {
        let error = DocScanError.modelLoadFailed("out of memory")
        XCTAssertEqual(error.errorDescription, "Failed to load model: out of memory")
    }

    func testModelNotFoundErrorDescription() {
        let error = DocScanError.modelNotFound("Qwen2-VL-2B")
        XCTAssertEqual(error.errorDescription, "Model not found: Qwen2-VL-2B")
    }

    func testInferenceErrorDescription() {
        let error = DocScanError.inferenceError("token limit exceeded")
        XCTAssertEqual(error.errorDescription, "Inference error: token limit exceeded")
    }

    func testFileNotFoundErrorDescription() {
        let error = DocScanError.fileNotFound("/path/to/file.pdf")
        XCTAssertEqual(error.errorDescription, "File not found: /path/to/file.pdf")
    }

    func testFileOperationFailedErrorDescription() {
        let error = DocScanError.fileOperationFailed("permission denied")
        XCTAssertEqual(error.errorDescription, "File operation failed: permission denied")
    }

    func testConfigurationErrorDescription() {
        let error = DocScanError.configurationError("invalid YAML")
        XCTAssertEqual(error.errorDescription, "Configuration error: invalid YAML")
    }

    func testNotAnInvoiceErrorDescription() {
        let error = DocScanError.notAnInvoice
        XCTAssertEqual(error.errorDescription, "Document is not an invoice")
    }

    func testExtractionFailedErrorDescription() {
        let error = DocScanError.extractionFailed("could not find date")
        XCTAssertEqual(error.errorDescription, "Failed to extract invoice data: could not find date")
    }

    func testInsufficientDiskSpaceErrorDescription() {
        let error = DocScanError.insufficientDiskSpace(required: 5_000_000_000, available: 1_000_000_000)
        XCTAssertEqual(error.errorDescription, "Insufficient disk space: 5.00 GB required, 1.00 GB available")
    }

    func testInsufficientDiskSpaceErrorDescriptionWithDecimalValues() {
        let error = DocScanError.insufficientDiskSpace(required: 2_500_000_000, available: 500_000_000)
        XCTAssertEqual(error.errorDescription, "Insufficient disk space: 2.50 GB required, 0.50 GB available")
    }

    // MARK: - LocalizedError Conformance Tests

    func testDocScanErrorConformsToLocalizedError() {
        let errors: [DocScanError] = [
            .invalidPDF("test"),
            .pdfConversionFailed("test"),
            .modelLoadFailed("test"),
            .modelNotFound("test"),
            .inferenceError("test"),
            .fileNotFound("test"),
            .fileOperationFailed("test"),
            .configurationError("test"),
            .notAnInvoice,
            .extractionFailed("test"),
            .insufficientDiskSpace(required: 1, available: 0)
        ]

        for error in errors {
            // All errors should have non-nil errorDescription
            XCTAssertNotNil(error.errorDescription, "Error \(error) should have a description")
            // localizedDescription should match errorDescription
            XCTAssertEqual(error.localizedDescription, error.errorDescription)
        }
    }

    func testTimeoutErrorConformsToLocalizedError() {
        let error = TimeoutError()
        XCTAssertNotNil(error.errorDescription)
        XCTAssertEqual(error.localizedDescription, error.errorDescription)
    }

    // MARK: - Error Throwing Tests

    func testThrowingDocScanError() {
        func throwFileNotFound() throws {
            throw DocScanError.fileNotFound("/test/path")
        }

        XCTAssertThrowsError(try throwFileNotFound()) { error in
            guard let docScanError = error as? DocScanError else {
                XCTFail("Expected DocScanError")
                return
            }
            if case .fileNotFound(let path) = docScanError {
                XCTAssertEqual(path, "/test/path")
            } else {
                XCTFail("Expected fileNotFound error")
            }
        }
    }

    func testThrowingTimeoutError() {
        func throwTimeout() throws {
            throw TimeoutError()
        }

        XCTAssertThrowsError(try throwTimeout()) { error in
            XCTAssertTrue(error is TimeoutError)
        }
    }
}
