@testable import DocScanCore
import XCTest

/// Tests for TimeoutError and TimeoutError.withTimeout() async utility.
final class TimeoutErrorTests: XCTestCase {
    // MARK: - TimeoutError properties

    func testTimeoutErrorDescription() {
        let error = TimeoutError()
        XCTAssertEqual(error.errorDescription, "Operation timed out")
    }

    func testTimeoutErrorLocalizedDescription() {
        let error = TimeoutError()
        XCTAssertEqual(error.localizedDescription, "Operation timed out")
    }

    // MARK: - withTimeout: Operation completes before timeout

    func testOperationCompletesBeforeTimeout() async throws {
        let result = try await TimeoutError.withTimeout(seconds: 5.0) {
            "success"
        }
        XCTAssertEqual(result, "success")
    }

    func testFastOperationReturnsCorrectValue() async throws {
        let result = try await TimeoutError.withTimeout(seconds: 5.0) {
            42
        }
        XCTAssertEqual(result, 42)
    }

    // MARK: - withTimeout: Operation exceeds timeout

    func testOperationExceedsTimeoutThrows() async {
        do {
            _ = try await TimeoutError.withTimeout(seconds: 0.1) {
                try await Task.sleep(for: .seconds(10))
                return "should not reach"
            }
            XCTFail("Expected TimeoutError")
        } catch is TimeoutError {
            // Expected
        } catch {
            XCTFail("Expected TimeoutError, got \(error)")
        }
    }

    // MARK: - withTimeout: Operation throws its own error

    func testOperationErrorPropagates() async {
        do {
            _ = try await TimeoutError.withTimeout(seconds: 5.0) {
                throw DocScanError.inferenceError("test error")
            }
            XCTFail("Expected DocScanError")
        } catch let error as DocScanError {
            if case let .inferenceError(msg) = error {
                XCTAssertEqual(msg, "test error")
            } else {
                XCTFail("Expected inferenceError, got \(error)")
            }
        } catch {
            XCTFail("Expected DocScanError, got \(error)")
        }
    }

    // MARK: - withTimeout: Return types

    func testWithTimeoutReturnsOptional() async throws {
        let result: String? = try await TimeoutError.withTimeout(seconds: 5.0) {
            nil
        }
        XCTAssertNil(result)
    }

    func testWithTimeoutReturnsTuple() async throws {
        let result = try await TimeoutError.withTimeout(seconds: 5.0) {
            (1, "two")
        }
        XCTAssertEqual(result.0, 1)
        XCTAssertEqual(result.1, "two")
    }
}
