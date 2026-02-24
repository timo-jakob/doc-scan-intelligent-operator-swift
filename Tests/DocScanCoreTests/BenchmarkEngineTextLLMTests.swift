@testable import DocScanCore
import XCTest

/// Mock TextLLM manager for benchmark tests. Returns controlled responses for both
/// categorization (generate) and extraction without loading a real model.
///
/// `@unchecked Sendable` is safe here because this mock is only mutated during
/// single-threaded test setup (before any async work begins) and read during
/// sequential test execution.
class BenchmarkMockTextLLMManager: TextLLMManager, @unchecked Sendable {
    /// Response returned by `generate()` — controls categorization (YES/NO)
    var generateResponse: String = "YES"

    /// Result returned by `extractData()` — controls extraction scoring
    var mockExtractionResult = ExtractionResult(date: nil, secondaryField: nil, patientName: nil)

    /// Whether generate should throw
    var generateError: Error?

    init() {
        super.init(config: Configuration())
    }

    override func extractData(
        for _: DocumentType,
        from _: String
    ) async throws -> ExtractionResult {
        mockExtractionResult
    }

    override func generate(
        systemPrompt _: String,
        userPrompt _: String,
        maxTokens _: Int
    ) async throws -> String {
        if let error = generateError {
            throw error
        }
        return generateResponse
    }
}

/// Mock TextLLM factory for testing.
/// When a mock manager is explicitly set via `setMockManager()`, it survives
/// `releaseTextLLM()` and `preloadTextLLM()` so the benchmark flow can use it.
actor MockTextLLMOnlyFactory: TextLLMOnlyFactory {
    private var mockManager: TextLLMManager?
    private var explicitlySet = false
    var preloadCalled = false
    var releaseCalled = false
    var preloadError: Error?

    func preloadTextLLM(modelName _: String, config _: Configuration) async throws {
        preloadCalled = true
        if let error = preloadError {
            throw error
        }
    }

    func makeTextLLMManager() -> TextLLMManager? {
        mockManager
    }

    func releaseTextLLM() {
        releaseCalled = true
        if !explicitlySet {
            mockManager = nil
        }
    }

    func setPreloadError(_ error: Error) {
        preloadError = error
    }

    func setMockManager(_ manager: TextLLMManager?) {
        mockManager = manager
        explicitlySet = manager != nil
    }
}

final class BenchmarkEngineTextLLMTests: XCTestCase {
    var engine: BenchmarkEngine!

    override func setUp() {
        super.setUp()
        engine = BenchmarkEngine(
            configuration: Configuration(),
            documentType: .invoice
        )
    }

    // MARK: - TextLLMDocumentResult Scoring

    func testTextLLMScore2ForFullyCorrect() {
        let result = TextLLMDocumentResult(
            filename: "invoice.pdf",
            isPositiveSample: true,
            categorizationCorrect: true,
            extractionCorrect: true
        )
        XCTAssertEqual(result.score, 2)
    }

    func testTextLLMScore1ForPartiallyCorrect() {
        let result = TextLLMDocumentResult(
            filename: "invoice.pdf",
            isPositiveSample: true,
            categorizationCorrect: true,
            extractionCorrect: false
        )
        XCTAssertEqual(result.score, 1)
    }

    func testTextLLMScore0ForFullyWrong() {
        let result = TextLLMDocumentResult(
            filename: "invoice.pdf",
            isPositiveSample: true,
            categorizationCorrect: false,
            extractionCorrect: false
        )
        XCTAssertEqual(result.score, 0)
    }

    func testTextLLMNegativeCorrectlyRejected() {
        // Correct rejection of negative sample → 2 points
        let result = TextLLMDocumentResult(
            filename: "letter.pdf",
            isPositiveSample: false,
            categorizationCorrect: true,
            extractionCorrect: true
        )
        XCTAssertEqual(result.score, 2)
    }

    func testTextLLMNegativeFalsePositive() {
        // False positive on negative sample → 0 points
        let result = TextLLMDocumentResult(
            filename: "letter.pdf",
            isPositiveSample: false,
            categorizationCorrect: false,
            extractionCorrect: false
        )
        XCTAssertEqual(result.score, 0)
    }

    // MARK: - TextLLMBenchmarkResult Aggregation

    func testTextLLMBenchmarkResultCounts() {
        let results = [
            TextLLMDocumentResult(filename: "a.pdf", isPositiveSample: true,
                                  categorizationCorrect: true, extractionCorrect: true),
            TextLLMDocumentResult(filename: "b.pdf", isPositiveSample: true,
                                  categorizationCorrect: true, extractionCorrect: false),
            TextLLMDocumentResult(filename: "c.pdf", isPositiveSample: false,
                                  categorizationCorrect: false, extractionCorrect: false),
        ]
        let benchmark = TextLLMBenchmarkResult.from(
            modelName: "test/text",
            documentResults: results,
            elapsedSeconds: 20.0
        )

        XCTAssertEqual(benchmark.fullyCorrectCount, 1) // score == 2
        XCTAssertEqual(benchmark.partiallyCorrectCount, 1) // score == 1
        XCTAssertEqual(benchmark.fullyWrongCount, 1) // score == 0
        XCTAssertEqual(benchmark.totalScore, 3) // 2 + 1 + 0
        XCTAssertEqual(benchmark.maxScore, 6) // 2 * 3
    }

    func testTextLLMBenchmarkDisqualifiedOnPreloadFailure() async {
        let factory = MockTextLLMOnlyFactory()
        await factory.setPreloadError(DocScanError.modelLoadFailed("test error"))

        let context = TextLLMBenchmarkContext(
            ocrTexts: [:], groundTruths: [:],
            timeoutSeconds: 10, textLLMFactory: factory
        )
        let result = await engine.benchmarkTextLLM(
            modelName: "test/model",
            positivePDFs: [],
            negativePDFs: [],
            context: context
        )

        XCTAssertTrue(result.isDisqualified)
        XCTAssertTrue(result.disqualificationReason?.contains("Failed to load") ?? false)
    }

    func testTextLLMBenchmarkElapsedTimeRecorded() {
        let results = [
            TextLLMDocumentResult(filename: "a.pdf", isPositiveSample: true,
                                  categorizationCorrect: true, extractionCorrect: true),
        ]
        let benchmark = TextLLMBenchmarkResult.from(
            modelName: "test/text",
            documentResults: results,
            elapsedSeconds: 33.7
        )
        XCTAssertEqual(benchmark.elapsedSeconds, 33.7)
    }

    // MARK: - TextLLM Benchmark Happy Path

    func testBenchmarkTextLLMHappyPathWithEmptyDocs() async {
        let factory = MockTextLLMOnlyFactory()
        let context = TextLLMBenchmarkContext(
            ocrTexts: [:], groundTruths: [:],
            timeoutSeconds: 10, textLLMFactory: factory
        )

        let result = await engine.benchmarkTextLLM(
            modelName: "test/mock-text",
            positivePDFs: [],
            negativePDFs: [],
            context: context
        )

        XCTAssertFalse(result.isDisqualified)
        XCTAssertEqual(result.modelName, "test/mock-text")
        XCTAssertEqual(result.documentResults.count, 0)
        XCTAssertEqual(result.totalScore, 0)
        XCTAssertEqual(result.maxScore, 0)
        XCTAssertEqual(result.score, 0)
        XCTAssertGreaterThanOrEqual(result.elapsedSeconds, 0)
    }

    // MARK: - TextLLM Document-Level Edge Cases

    func testBenchmarkTextLLMDocumentMissingOCRText() async {
        // When ocrTexts is empty for a document, both flags should be false
        let factory = MockTextLLMOnlyFactory()
        let context = TextLLMBenchmarkContext(
            ocrTexts: [:], // No OCR text for any document
            groundTruths: [:],
            timeoutSeconds: 10,
            textLLMFactory: factory
        )

        let result = await engine.benchmarkTextLLM(
            modelName: "test/mock-text",
            positivePDFs: ["/fake/invoice.pdf"],
            negativePDFs: [],
            context: context
        )

        XCTAssertFalse(result.isDisqualified)
        XCTAssertEqual(result.documentResults.count, 1)
        let docResult = result.documentResults[0]
        XCTAssertFalse(docResult.categorizationCorrect)
        XCTAssertFalse(docResult.extractionCorrect)
        XCTAssertEqual(docResult.score, 0)
    }

    func testBenchmarkTextLLMDocumentNilFactory() async {
        // MockTextLLMOnlyFactory returns nil for makeTextLLMManager by default
        let factory = MockTextLLMOnlyFactory()
        let context = TextLLMBenchmarkContext(
            ocrTexts: ["/fake/invoice.pdf": "Some invoice text with Rechnung"],
            groundTruths: [:],
            timeoutSeconds: 10,
            textLLMFactory: factory
        )

        let result = await engine.benchmarkTextLLM(
            modelName: "test/mock-text",
            positivePDFs: ["/fake/invoice.pdf"],
            negativePDFs: [],
            context: context
        )

        XCTAssertFalse(result.isDisqualified)
        XCTAssertEqual(result.documentResults.count, 1)
        let docResult = result.documentResults[0]
        // nil TextLLM → both false
        XCTAssertFalse(docResult.categorizationCorrect)
        XCTAssertFalse(docResult.extractionCorrect)
    }

    func testBenchmarkTextLLMNegativeSampleWithNilFactory() async {
        // Negative sample with nil TextLLM → both flags false
        let factory = MockTextLLMOnlyFactory()
        let context = TextLLMBenchmarkContext(
            ocrTexts: ["/fake/letter.pdf": "Some random text about weather"],
            groundTruths: [:],
            timeoutSeconds: 10,
            textLLMFactory: factory
        )

        let result = await engine.benchmarkTextLLM(
            modelName: "test/mock-text",
            positivePDFs: [],
            negativePDFs: ["/fake/letter.pdf"],
            context: context
        )

        XCTAssertFalse(result.isDisqualified)
        XCTAssertEqual(result.documentResults.count, 1)
        let docResult = result.documentResults[0]
        XCTAssertFalse(docResult.isPositiveSample)
        XCTAssertFalse(docResult.categorizationCorrect)
        XCTAssertFalse(docResult.extractionCorrect)
    }

    func testBenchmarkTextLLMEmptyOCRTextTreatedAsMissing() async {
        // Empty string OCR text should be treated as missing
        let factory = MockTextLLMOnlyFactory()
        let context = TextLLMBenchmarkContext(
            ocrTexts: ["/fake/invoice.pdf": ""], // Empty string
            groundTruths: [:],
            timeoutSeconds: 10,
            textLLMFactory: factory
        )

        let result = await engine.benchmarkTextLLM(
            modelName: "test/mock-text",
            positivePDFs: ["/fake/invoice.pdf"],
            negativePDFs: [],
            context: context
        )

        XCTAssertEqual(result.documentResults.count, 1)
        let docResult = result.documentResults[0]
        // Empty OCR text guard triggers → both false
        XCTAssertFalse(docResult.categorizationCorrect)
        XCTAssertFalse(docResult.extractionCorrect)
    }

    // MARK: - Memory Disqualification

    func testBenchmarkTextLLMDisqualifiedOnInsufficientMemory() async {
        let factory = MockTextLLMOnlyFactory()
        let context = TextLLMBenchmarkContext(
            ocrTexts: [:], groundTruths: [:],
            timeoutSeconds: 10, textLLMFactory: factory
        )

        // Use an absurdly large model name to trigger memory check
        let result = await engine.benchmarkTextLLM(
            modelName: "org/Model-999999B-4bit",
            positivePDFs: [],
            negativePDFs: [],
            context: context
        )

        XCTAssertTrue(result.isDisqualified)
        XCTAssertTrue(result.disqualificationReason?.contains("Insufficient memory") ?? false)
    }

    // MARK: - Memory Estimation

    func testMemoryEstimateForTextOnly() {
        let memoryMB = BenchmarkEngine.estimateMemoryMB(vlm: "", text: "org/Model-7B-4bit")
        XCTAssertGreaterThan(memoryMB, 0)
    }

    func testMemoryEstimateForBothEmpty() {
        let memoryMB = BenchmarkEngine.estimateMemoryMB(vlm: "", text: "")
        XCTAssertEqual(memoryMB, 0)
    }
}
