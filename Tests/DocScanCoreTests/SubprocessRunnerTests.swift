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
        let workerOutput = BenchmarkWorkerOutput.vlm(
            VLMBenchmarkResult.disqualified(modelName: "m", reason: "test")
        )
        let result = SubprocessResult.success(workerOutput)

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

    // MARK: - Overall Timeout Computation

    func testOverallTimeoutComputation() {
        let input = BenchmarkWorkerInput(
            phase: .vlm,
            modelName: "test/model",
            pdfSet: BenchmarkPDFSet(positivePDFs: ["/a.pdf", "/b.pdf"], negativePDFs: ["/c.pdf"]),
            timeoutSeconds: 30.0,
            documentType: .invoice,
            configuration: Configuration.defaultConfiguration
        )

        let timeout = SubprocessRunner.overallTimeout(for: input)

        // 3 docs × 30s + 300s buffer = 390s
        XCTAssertEqual(timeout, 390.0)
    }

    func testOverallTimeoutWithZeroDocuments() {
        let input = BenchmarkWorkerInput(
            phase: .vlm,
            modelName: "test/model",
            pdfSet: BenchmarkPDFSet(positivePDFs: [], negativePDFs: []),
            timeoutSeconds: 30.0,
            documentType: .invoice,
            configuration: Configuration.defaultConfiguration
        )

        let timeout = SubprocessRunner.overallTimeout(for: input)

        // 0 docs × 30s + 300s buffer = 300s (just the loading buffer)
        XCTAssertEqual(timeout, SubprocessRunner.modelLoadingBufferSeconds)
    }

    func testOverallTimeoutScalesWithDocumentCount() {
        let smallInput = BenchmarkWorkerInput(
            phase: .vlm,
            modelName: "test/model",
            pdfSet: BenchmarkPDFSet(positivePDFs: ["/a.pdf"], negativePDFs: []),
            timeoutSeconds: 10.0,
            documentType: .invoice,
            configuration: Configuration.defaultConfiguration
        )

        let largeInput = BenchmarkWorkerInput(
            phase: .vlm,
            modelName: "test/model",
            pdfSet: BenchmarkPDFSet(
                positivePDFs: ["/a.pdf", "/b.pdf", "/c.pdf", "/d.pdf", "/e.pdf"],
                negativePDFs: ["/f.pdf", "/g.pdf", "/h.pdf", "/i.pdf", "/j.pdf"]
            ),
            timeoutSeconds: 10.0,
            documentType: .invoice,
            configuration: Configuration.defaultConfiguration
        )

        let smallTimeout = SubprocessRunner.overallTimeout(for: smallInput)
        let largeTimeout = SubprocessRunner.overallTimeout(for: largeInput)

        // 1 × 10 + 300 = 310 vs 10 × 10 + 300 = 400
        XCTAssertEqual(smallTimeout, 310.0)
        XCTAssertEqual(largeTimeout, 400.0)
        XCTAssertTrue(largeTimeout > smallTimeout)
    }

    // MARK: - Integration: run() spawns a real subprocess

    /// The test runner binary does not have a `benchmark-worker` subcommand,
    /// so the spawned process exits non-zero. This exercises the full process
    /// lifecycle: temp file creation, process launch, termination handling,
    /// and temp file cleanup.
    func testRunReturnsNonZeroExitForUnknownSubcommand() async throws {
        let runner = SubprocessRunner()
        defer { runner.cleanup() }
        let input = BenchmarkWorkerInput(
            phase: .vlm,
            modelName: "test/model",
            pdfSet: BenchmarkPDFSet(positivePDFs: [], negativePDFs: []),
            timeoutSeconds: 10.0,
            documentType: .invoice,
            configuration: Configuration.defaultConfiguration
        )

        let result = try await runner.run(input: input)

        switch result {
        case let .crashed(exitCode, _):
            // The test runner exits non-zero when given an unknown subcommand
            XCTAssertNotEqual(exitCode, 0)
        case .decodingFailed:
            // Also acceptable — process may exit 0 but produce no valid output
            break
        case .success:
            XCTFail("Expected crash or decoding failure from test runner binary")
        }
    }

    // MARK: - makeDisqualifiedOutput

    func testMakeDisqualifiedOutputVLM() {
        let input = BenchmarkWorkerInput(
            phase: .vlm,
            modelName: "test/vlm",
            pdfSet: BenchmarkPDFSet(positivePDFs: [], negativePDFs: []),
            timeoutSeconds: 30.0,
            documentType: .invoice,
            configuration: Configuration.defaultConfiguration
        )

        let output = input.makeDisqualifiedOutput(reason: "crashed")

        XCTAssertNotNil(output.vlmResult)
        XCTAssertNil(output.textLLMResult)
        XCTAssertTrue(output.vlmResult?.isDisqualified ?? false)
        XCTAssertEqual(output.vlmResult?.disqualificationReason, "crashed")
        XCTAssertEqual(output.vlmResult?.modelName, "test/vlm")
    }

    func testMakeDisqualifiedOutputTextLLM() {
        let input = BenchmarkWorkerInput(
            phase: .textLLM,
            modelName: "test/text",
            pdfSet: BenchmarkPDFSet(positivePDFs: [], negativePDFs: []),
            timeoutSeconds: 30.0,
            documentType: .invoice,
            configuration: Configuration.defaultConfiguration
        )

        let output = input.makeDisqualifiedOutput(reason: "timeout")

        XCTAssertNil(output.vlmResult)
        XCTAssertNotNil(output.textLLMResult)
        XCTAssertTrue(output.textLLMResult?.isDisqualified ?? false)
        XCTAssertEqual(output.textLLMResult?.disqualificationReason, "timeout")
        XCTAssertEqual(output.textLLMResult?.modelName, "test/text")
    }
}
