import AppKit
@testable import DocScanCore
import XCTest

/// Mock VLM factory for testing
actor MockVLMOnlyFactory: VLMOnlyFactory {
    var mockProvider: BenchmarkMockVLMProvider?
    var preloadCalled = false
    var releaseCalled = false
    var preloadError: Error?

    func preloadVLM(modelName _: String, config _: Configuration) async throws {
        preloadCalled = true
        if let error = preloadError {
            throw error
        }
        mockProvider = BenchmarkMockVLMProvider()
    }

    func makeVLMProvider() -> VLMProvider? {
        mockProvider
    }

    func releaseVLM() {
        releaseCalled = true
        mockProvider = nil
    }

    func setResponse(_ response: String) {
        mockProvider?.mockResponse = response
    }

    func setPreloadError(_ error: Error) {
        preloadError = error
    }
}

/// Mock VLM provider for testing
class BenchmarkMockVLMProvider: VLMProvider, @unchecked Sendable {
    var mockResponse: String = "Yes"
    var callCount = 0

    func generateFromImage(
        _: NSImage,
        prompt _: String,
        modelName _: String?
    ) async throws -> String {
        callCount += 1
        return mockResponse
    }
}

final class BenchmarkEngineVLMTests: XCTestCase {
    var engine: BenchmarkEngine!
    var tempDir: URL!
    var positivePDFs: [String]!
    var negativePDFs: [String]!

    override func setUp() {
        super.setUp()
        engine = BenchmarkEngine(
            configuration: Configuration(),
            documentType: .invoice,
            verbose: false
        )
    }

    // MARK: - parseYesNoResponse

    func testParseYesNoResponseYes() {
        XCTAssertTrue(BenchmarkEngine.parseYesNoResponse("Yes"))
        XCTAssertTrue(BenchmarkEngine.parseYesNoResponse("YES"))
        XCTAssertTrue(BenchmarkEngine.parseYesNoResponse("yes"))
        XCTAssertTrue(BenchmarkEngine.parseYesNoResponse("Yes, this is an invoice"))
    }

    func testParseYesNoResponseNo() {
        XCTAssertFalse(BenchmarkEngine.parseYesNoResponse("No"))
        XCTAssertFalse(BenchmarkEngine.parseYesNoResponse("NO"))
        XCTAssertFalse(BenchmarkEngine.parseYesNoResponse("no"))
    }

    func testParseYesNoResponseGerman() {
        XCTAssertTrue(BenchmarkEngine.parseYesNoResponse("Ja"))
        XCTAssertTrue(BenchmarkEngine.parseYesNoResponse("ja"))
    }

    func testParseYesNoResponseAmbiguous() {
        // Empty or unrecognized responses default to false
        XCTAssertFalse(BenchmarkEngine.parseYesNoResponse(""))
        XCTAssertFalse(BenchmarkEngine.parseYesNoResponse("maybe"))
    }

    // MARK: - VLM Benchmark Result Construction

    func testVLMBenchmarkResultTruePositive() {
        let result = VLMDocumentResult(
            filename: "invoice.pdf",
            isPositiveSample: true,
            predictedIsMatch: true
        )
        XCTAssertTrue(result.correct)
        XCTAssertEqual(result.score, 1)
    }

    func testVLMBenchmarkResultTrueNegative() {
        let result = VLMDocumentResult(
            filename: "letter.pdf",
            isPositiveSample: false,
            predictedIsMatch: false
        )
        XCTAssertTrue(result.correct)
        XCTAssertEqual(result.score, 1)
    }

    func testVLMBenchmarkResultFalsePositive() {
        let result = VLMDocumentResult(
            filename: "letter.pdf",
            isPositiveSample: false,
            predictedIsMatch: true
        )
        XCTAssertFalse(result.correct)
        XCTAssertEqual(result.score, 0)
    }

    func testVLMBenchmarkResultFalseNegative() {
        let result = VLMDocumentResult(
            filename: "invoice.pdf",
            isPositiveSample: true,
            predictedIsMatch: false
        )
        XCTAssertFalse(result.correct)
        XCTAssertEqual(result.score, 0)
    }

    // MARK: - VLM Benchmark Aggregation

    func testVLMBenchmarkElapsedTimeRecorded() {
        let results = [
            VLMDocumentResult(filename: "a.pdf", isPositiveSample: true, predictedIsMatch: true),
        ]
        let benchmark = VLMBenchmarkResult.from(
            modelName: "test/vlm",
            documentResults: results,
            elapsedSeconds: 42.5
        )
        XCTAssertEqual(benchmark.elapsedSeconds, 42.5)
    }

    func testVLMBenchmarkDisqualifiedModelHasZeroScore() {
        let result = VLMBenchmarkResult.disqualified(
            modelName: "test/vlm",
            reason: "Out of memory"
        )
        XCTAssertEqual(result.score, 0)
        XCTAssertTrue(result.isDisqualified)
        XCTAssertEqual(result.disqualificationReason, "Out of memory")
    }

    // MARK: - Memory Estimation

    func testMemoryEstimateForVLMOnly() {
        let memoryMB = BenchmarkEngine.estimateMemoryMB(vlm: "org/Model-7B-4bit", text: "")
        XCTAssertGreaterThan(memoryMB, 0)
    }

    func testMemoryEstimateForUnknownModel() {
        let memoryMB = BenchmarkEngine.estimateMemoryMB(vlm: "unknown-model", text: "")
        XCTAssertEqual(memoryMB, 0)
    }
}
