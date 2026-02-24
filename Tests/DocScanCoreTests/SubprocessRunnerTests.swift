@testable import DocScanCore
import XCTest

final class SubprocessRunnerTests: XCTestCase {
    // MARK: - resolveExecutablePath

    func testResolveExecutablePathReturnsAbsolutePath() {
        let path = SubprocessRunner.resolveExecutablePath()
        XCTAssertTrue(
            path.hasPrefix("/"),
            "Expected absolute path, got: \(path)"
        )
    }

    // MARK: - SubprocessResult Enum Cases

    func testSubprocessResultSuccess() {
        let output = BenchmarkWorkerOutput(
            vlmResult: VLMBenchmarkResult.disqualified(modelName: "m", reason: "test")
        )
        let result = SubprocessResult.success(output)

        if case let .success(output) = result {
            XCTAssertNotNil(output.vlmResult)
            XCTAssertNil(output.textLLMResult)
        } else {
            XCTFail("Expected .success case")
        }
    }

    func testSubprocessResultCrashedWithSignal() {
        let result = SubprocessResult.crashed(exitCode: 6, signal: 6)

        if case let .crashed(exitCode, signal) = result {
            XCTAssertEqual(exitCode, 6)
            XCTAssertEqual(signal, 6)
        } else {
            XCTFail("Expected .crashed case")
        }
    }

    func testSubprocessResultCrashedWithoutSignal() {
        let result = SubprocessResult.crashed(exitCode: 1, signal: nil)

        if case let .crashed(exitCode, signal) = result {
            XCTAssertEqual(exitCode, 1)
            XCTAssertNil(signal)
        } else {
            XCTFail("Expected .crashed case")
        }
    }

    func testSubprocessResultDecodingFailed() {
        let result = SubprocessResult.decodingFailed("bad json")

        if case let .decodingFailed(message) = result {
            XCTAssertEqual(message, "bad json")
        } else {
            XCTFail("Expected .decodingFailed case")
        }
    }
}
