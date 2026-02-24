@testable import DocScanCore
import XCTest

// MARK: - TextLLM With Mock Manager (categorization + extraction paths)

/// Tests that exercise the full categorization + extraction flow using BenchmarkMockTextLLMManager.
/// Split from BenchmarkEngineTextLLMTests to stay within SwiftLint length limits.
final class BenchmarkEngineTextLLMMockManagerTests: XCTestCase {
    var engine: BenchmarkEngine!

    override func setUp() {
        super.setUp()
        engine = BenchmarkEngine(
            configuration: Configuration(),
            documentType: .invoice,
            verbose: false
        )
    }

    func testPositiveCategorizationCorrect() async {
        let mockLLM = BenchmarkMockTextLLMManager()
        mockLLM.generateResponse = "YES" // Categorize as match

        let factory = MockTextLLMOnlyFactory()
        await factory.setMockManager(mockLLM)

        let groundTruth = GroundTruth(
            isMatch: true, documentType: .invoice,
            date: "2025-01-15", secondaryField: "Acme_Corp"
        )

        let context = TextLLMBenchmarkContext(
            ocrTexts: ["/fake/invoice.pdf": "Rechnung invoice text"],
            groundTruths: ["/fake/invoice.pdf": groundTruth],
            timeoutSeconds: 10, textLLMFactory: factory
        )

        let result = await engine.benchmarkTextLLM(
            modelName: "test/mock-text",
            positivePDFs: ["/fake/invoice.pdf"],
            negativePDFs: [],
            context: context
        )

        XCTAssertEqual(result.documentResults.count, 1)
        let docResult = result.documentResults[0]
        XCTAssertTrue(docResult.categorizationCorrect)
    }

    func testPositiveCategorizationWrong() async {
        let mockLLM = BenchmarkMockTextLLMManager()
        mockLLM.generateResponse = "NO" // Wrong categorization for positive sample

        let factory = MockTextLLMOnlyFactory()
        await factory.setMockManager(mockLLM)

        let context = TextLLMBenchmarkContext(
            ocrTexts: ["/fake/invoice.pdf": "Rechnung invoice text"],
            groundTruths: [:],
            timeoutSeconds: 10, textLLMFactory: factory
        )

        let result = await engine.benchmarkTextLLM(
            modelName: "test/mock-text",
            positivePDFs: ["/fake/invoice.pdf"],
            negativePDFs: [],
            context: context
        )

        XCTAssertEqual(result.documentResults.count, 1)
        let docResult = result.documentResults[0]
        XCTAssertFalse(docResult.categorizationCorrect)
        XCTAssertFalse(docResult.extractionCorrect)
    }

    func testNegativeCorrectRejection() async {
        let mockLLM = BenchmarkMockTextLLMManager()
        mockLLM.generateResponse = "NO" // Correct rejection of negative sample

        let factory = MockTextLLMOnlyFactory()
        await factory.setMockManager(mockLLM)

        let context = TextLLMBenchmarkContext(
            ocrTexts: ["/fake/letter.pdf": "Just a random letter about weather"],
            groundTruths: [:],
            timeoutSeconds: 10, textLLMFactory: factory
        )

        let result = await engine.benchmarkTextLLM(
            modelName: "test/mock-text",
            positivePDFs: [],
            negativePDFs: ["/fake/letter.pdf"],
            context: context
        )

        XCTAssertEqual(result.documentResults.count, 1)
        let docResult = result.documentResults[0]
        XCTAssertTrue(docResult.categorizationCorrect)
        XCTAssertTrue(docResult.extractionCorrect)
    }

    func testNegativeFalsePositive() async {
        let mockLLM = BenchmarkMockTextLLMManager()
        mockLLM.generateResponse = "YES" // False positive on negative sample

        let factory = MockTextLLMOnlyFactory()
        await factory.setMockManager(mockLLM)

        let context = TextLLMBenchmarkContext(
            ocrTexts: ["/fake/letter.pdf": "Just a random letter"],
            groundTruths: [:],
            timeoutSeconds: 10, textLLMFactory: factory
        )

        let result = await engine.benchmarkTextLLM(
            modelName: "test/mock-text",
            positivePDFs: [],
            negativePDFs: ["/fake/letter.pdf"],
            context: context
        )

        XCTAssertEqual(result.documentResults.count, 1)
        let docResult = result.documentResults[0]
        XCTAssertFalse(docResult.categorizationCorrect)
    }

    func testCategorizationError() async {
        let mockLLM = BenchmarkMockTextLLMManager()
        mockLLM.generateError = DocScanError.inferenceError("mock error")

        let factory = MockTextLLMOnlyFactory()
        await factory.setMockManager(mockLLM)

        let context = TextLLMBenchmarkContext(
            ocrTexts: ["/fake/invoice.pdf": "Some text"],
            groundTruths: [:],
            timeoutSeconds: 10, textLLMFactory: factory
        )

        let result = await engine.benchmarkTextLLM(
            modelName: "test/mock-text",
            positivePDFs: ["/fake/invoice.pdf"],
            negativePDFs: [],
            context: context
        )

        XCTAssertEqual(result.documentResults.count, 1)
        let docResult = result.documentResults[0]
        // Error during categorization → nil → both false
        XCTAssertFalse(docResult.categorizationCorrect)
        XCTAssertFalse(docResult.extractionCorrect)
    }

    func testExtractionWithGroundTruth() async throws {
        let mockLLM = BenchmarkMockTextLLMManager()
        mockLLM.generateResponse = "YES"
        // Extraction returns matching date and company
        let calendar = Calendar.current
        let date = try XCTUnwrap(calendar.date(from: DateComponents(year: 2025, month: 1, day: 15)))
        mockLLM.mockExtractionResult = ExtractionResult(
            date: date, secondaryField: "Acme_Corp", patientName: nil
        )

        let factory = MockTextLLMOnlyFactory()
        await factory.setMockManager(mockLLM)

        let groundTruth = GroundTruth(
            isMatch: true, documentType: .invoice,
            date: "2025-01-15", secondaryField: "Acme_Corp"
        )

        let context = TextLLMBenchmarkContext(
            ocrTexts: ["/fake/invoice.pdf": "Rechnung Acme Corp 2025-01-15"],
            groundTruths: ["/fake/invoice.pdf": groundTruth],
            timeoutSeconds: 10, textLLMFactory: factory
        )

        let result = await engine.benchmarkTextLLM(
            modelName: "test/mock-text",
            positivePDFs: ["/fake/invoice.pdf"],
            negativePDFs: [],
            context: context
        )

        XCTAssertEqual(result.documentResults.count, 1)
        let docResult = result.documentResults[0]
        XCTAssertTrue(docResult.categorizationCorrect)
        XCTAssertTrue(docResult.extractionCorrect)
        XCTAssertEqual(docResult.score, 2)
    }

    func testExtractionMissingGroundTruth() async {
        let mockLLM = BenchmarkMockTextLLMManager()
        mockLLM.generateResponse = "YES"

        let factory = MockTextLLMOnlyFactory()
        await factory.setMockManager(mockLLM)

        // No ground truth for this PDF → extraction scores false
        let context = TextLLMBenchmarkContext(
            ocrTexts: ["/fake/invoice.pdf": "Rechnung text"],
            groundTruths: [:],
            timeoutSeconds: 10, textLLMFactory: factory
        )

        let result = await engine.benchmarkTextLLM(
            modelName: "test/mock-text",
            positivePDFs: ["/fake/invoice.pdf"],
            negativePDFs: [],
            context: context
        )

        XCTAssertEqual(result.documentResults.count, 1)
        let docResult = result.documentResults[0]
        XCTAssertTrue(docResult.categorizationCorrect)
        XCTAssertFalse(docResult.extractionCorrect)
    }
}
