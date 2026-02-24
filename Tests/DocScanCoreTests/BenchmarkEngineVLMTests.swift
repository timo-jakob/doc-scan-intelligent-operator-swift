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

    func generateFromImage(
        _: NSImage,
        prompt _: String,
        modelName _: String?
    ) async throws -> String {
        mockResponse
    }
}

/// Mock VLM provider that throws errors
class BenchmarkMockVLMProviderThrowing: VLMProvider, @unchecked Sendable {
    var errorToThrow: Error = DocScanError.inferenceError("mock error")

    func generateFromImage(
        _: NSImage,
        prompt _: String,
        modelName _: String?
    ) async throws -> String {
        throw errorToThrow
    }
}

/// Mock VLM factory that returns a nil provider (simulates unloaded model)
actor MockVLMOnlyFactoryNilProvider: VLMOnlyFactory {
    func preloadVLM(modelName _: String, config _: Configuration) async throws {}
    func makeVLMProvider() -> VLMProvider? {
        nil
    }

    func releaseVLM() {}
}

/// Mock VLM factory that returns a throwing provider
actor MockVLMOnlyFactoryThrowing: VLMOnlyFactory {
    var throwingProvider: BenchmarkMockVLMProviderThrowing?

    func preloadVLM(modelName _: String, config _: Configuration) async throws {
        throwingProvider = BenchmarkMockVLMProviderThrowing()
    }

    func makeVLMProvider() -> VLMProvider? {
        throwingProvider
    }

    func releaseVLM() {
        throwingProvider = nil
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

    // MARK: - VLM Benchmark Happy Path

    func testBenchmarkVLMHappyPath() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("BenchmarkVLMTest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Create a minimal valid PDF
        let positivePDF = tempDir.appendingPathComponent("invoice.pdf")
        let negativePDF = tempDir.appendingPathComponent("letter.pdf")
        for pdfURL in [positivePDF, negativePDF] {
            try createMinimalPDF(at: pdfURL)
        }

        let factory = MockVLMOnlyFactory()
        let result = await engine.benchmarkVLM(
            modelName: "test/mock-vlm",
            positivePDFs: [positivePDF.path],
            negativePDFs: [negativePDF.path],
            timeoutSeconds: 10,
            vlmFactory: factory
        )

        XCTAssertFalse(result.isDisqualified)
        XCTAssertEqual(result.modelName, "test/mock-vlm")
        XCTAssertEqual(result.documentResults.count, 2)
        XCTAssertGreaterThanOrEqual(result.elapsedSeconds, 0)
        // Mock responds "Yes" by default → positive=TP, negative=FP
        XCTAssertEqual(result.truePositives, 1)
        XCTAssertEqual(result.falsePositives, 1)
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

    // MARK: - VLM Provider Returns Nil

    func testBenchmarkVLMNilProviderScoresZero() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("BenchmarkVLMNilTest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let positivePDF = tempDir.appendingPathComponent("invoice.pdf")
        try createMinimalPDF(at: positivePDF)

        let factory = MockVLMOnlyFactoryNilProvider()
        let result = await engine.benchmarkVLM(
            modelName: "test/nil-vlm",
            positivePDFs: [positivePDF.path],
            negativePDFs: [],
            timeoutSeconds: 10,
            vlmFactory: factory
        )

        XCTAssertFalse(result.isDisqualified)
        XCTAssertEqual(result.documentResults.count, 1)
        // Nil provider → predictedIsMatch = false → positive sample = FN → score 0
        XCTAssertFalse(result.documentResults[0].predictedIsMatch)
        XCTAssertEqual(result.documentResults[0].score, 0)
    }

    // MARK: - VLM Error During Inference

    func testBenchmarkVLMErrorDuringInferenceScoresZero() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("BenchmarkVLMErrorTest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let positivePDF = tempDir.appendingPathComponent("invoice.pdf")
        let negativePDF = tempDir.appendingPathComponent("letter.pdf")
        try createMinimalPDF(at: positivePDF)
        try createMinimalPDF(at: negativePDF)

        let factory = MockVLMOnlyFactoryThrowing()
        let result = await engine.benchmarkVLM(
            modelName: "test/throwing-vlm",
            positivePDFs: [positivePDF.path],
            negativePDFs: [negativePDF.path],
            timeoutSeconds: 10,
            vlmFactory: factory
        )

        XCTAssertFalse(result.isDisqualified)
        XCTAssertEqual(result.documentResults.count, 2)
        // Error → predictedIsMatch = !isPositive → always wrong → score 0
        for docResult in result.documentResults {
            XCTAssertEqual(docResult.score, 0)
        }
    }

    // MARK: - VLM Preload Failure

    func testBenchmarkVLMPreloadFailureDisqualifies() async {
        let factory = MockVLMOnlyFactory()
        await factory.setPreloadError(DocScanError.modelLoadFailed("test preload error"))

        let result = await engine.benchmarkVLM(
            modelName: "test/bad-vlm",
            positivePDFs: [],
            negativePDFs: [],
            timeoutSeconds: 10,
            vlmFactory: factory
        )

        XCTAssertTrue(result.isDisqualified)
        XCTAssertTrue(result.disqualificationReason?.contains("Failed to load") ?? false)
        XCTAssertEqual(result.score, 0)
    }

    // MARK: - Helpers

    private func createMinimalPDF(at url: URL) throws {
        let pdfData = NSMutableData()
        guard let consumer = CGDataConsumer(data: pdfData as CFMutableData),
              let context = CGContext(consumer: consumer, mediaBox: nil, nil)
        else {
            throw DocScanError.pdfConversionFailed("Could not create PDF context")
        }
        var mediaBox = CGRect(x: 0, y: 0, width: 100, height: 100)
        context.beginPage(mediaBox: &mediaBox)
        context.endPage()
        context.closePDF()
        try (pdfData as Data).write(to: url)
    }
}
