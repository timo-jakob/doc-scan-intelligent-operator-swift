@testable import DocScanCore
import XCTest

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

    func testDocumentTypeMismatchErrorDescription() {
        let error = DocScanError.documentTypeMismatch("Invoice")
        XCTAssertEqual(error.errorDescription, "Document does not match type: Invoice")
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

    func testInvalidInputErrorDescription() {
        let msg = "PDF path cannot be empty. Use '.' to refer to the current directory."
        let error = DocScanError.invalidInput(msg)
        XCTAssertEqual(error.errorDescription, "Invalid input: \(msg)")
    }

    func testKeychainErrorDescription() {
        let error = DocScanError.keychainError("item not found")
        XCTAssertEqual(error.errorDescription, "Keychain error: item not found")
    }

    func testNetworkErrorDescription() {
        let error = DocScanError.networkError("connection refused")
        XCTAssertEqual(error.errorDescription, "Network error: connection refused")
    }

    func testHuggingFaceAPIErrorDescription() {
        let error = DocScanError.huggingFaceAPIError("rate limited")
        XCTAssertEqual(error.errorDescription, "Hugging Face API error: rate limited")
    }

    func testBenchmarkErrorDescription() {
        let error = DocScanError.benchmarkError("no ground truth files")
        XCTAssertEqual(error.errorDescription, "Benchmark error: no ground truth files")
    }

    func testMemoryInsufficientErrorDescription() {
        let error = DocScanError.memoryInsufficient(required: 8_000_000_000, available: 4_000_000_000)
        XCTAssertEqual(error.errorDescription, "Insufficient memory: 8000 MB required, 4000 MB available")
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
            .documentTypeMismatch("Invoice"),
            .extractionFailed("test"),
            .insufficientDiskSpace(required: 1, available: 0),
            .invalidInput("test"),
            .keychainError("test"),
            .networkError("test"),
            .huggingFaceAPIError("test"),
            .benchmarkError("test"),
            .memoryInsufficient(required: 1, available: 0),
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
            if case let .fileNotFound(path) = docScanError {
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
