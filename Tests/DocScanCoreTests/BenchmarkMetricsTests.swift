@testable import DocScanCore
import XCTest

final class BenchmarkMetricsTests: XCTestCase {
    // MARK: - VLMDocumentResult

    func testVLMDocumentResultCorrectPositive() {
        let result = VLMDocumentResult(
            filename: "invoice.pdf",
            isPositiveSample: true,
            predictedIsMatch: true
        )
        XCTAssertTrue(result.correct)
        XCTAssertEqual(result.score, 1)
    }

    func testVLMDocumentResultWrongPositive() {
        let result = VLMDocumentResult(
            filename: "invoice.pdf",
            isPositiveSample: true,
            predictedIsMatch: false
        )
        XCTAssertFalse(result.correct)
        XCTAssertEqual(result.score, 0)
    }

    func testVLMDocumentResultCorrectNegative() {
        let result = VLMDocumentResult(
            filename: "not_invoice.pdf",
            isPositiveSample: false,
            predictedIsMatch: false
        )
        XCTAssertTrue(result.correct)
        XCTAssertEqual(result.score, 1)
    }

    func testVLMDocumentResultFalsePositive() {
        let result = VLMDocumentResult(
            filename: "not_invoice.pdf",
            isPositiveSample: false,
            predictedIsMatch: true
        )
        XCTAssertFalse(result.correct)
        XCTAssertEqual(result.score, 0)
    }

    // MARK: - VLMBenchmarkResult

    func testVLMBenchmarkResultFromDocuments() {
        let results = [
            VLMDocumentResult(filename: "a.pdf", isPositiveSample: true, predictedIsMatch: true),
            VLMDocumentResult(filename: "b.pdf", isPositiveSample: true, predictedIsMatch: false),
            VLMDocumentResult(filename: "c.pdf", isPositiveSample: false, predictedIsMatch: false),
            VLMDocumentResult(filename: "d.pdf", isPositiveSample: false, predictedIsMatch: true),
        ]
        let benchmarkResult = VLMBenchmarkResult.from(
            modelName: "test/vlm",
            documentResults: results,
            elapsedSeconds: 10.0
        )

        XCTAssertEqual(benchmarkResult.totalScore, 2)
        XCTAssertEqual(benchmarkResult.maxScore, 4)
        XCTAssertEqual(benchmarkResult.score, 0.5)
        XCTAssertEqual(benchmarkResult.truePositives, 1)
        XCTAssertEqual(benchmarkResult.trueNegatives, 1)
        XCTAssertEqual(benchmarkResult.falsePositives, 1)
        XCTAssertEqual(benchmarkResult.falseNegatives, 1)
        XCTAssertEqual(benchmarkResult.elapsedSeconds, 10.0)
        XCTAssertFalse(benchmarkResult.isDisqualified)
    }

    func testVLMBenchmarkResultPerfectScore() {
        let results = [
            VLMDocumentResult(filename: "a.pdf", isPositiveSample: true, predictedIsMatch: true),
            VLMDocumentResult(filename: "b.pdf", isPositiveSample: false, predictedIsMatch: false),
        ]
        let benchmarkResult = VLMBenchmarkResult.from(
            modelName: "test/vlm",
            documentResults: results,
            elapsedSeconds: 5.0
        )

        XCTAssertEqual(benchmarkResult.score, 1.0)
        XCTAssertEqual(benchmarkResult.totalScore, 2)
        XCTAssertEqual(benchmarkResult.maxScore, 2)
    }

    func testVLMBenchmarkResultDisqualified() {
        let result = VLMBenchmarkResult.disqualified(
            modelName: "test/vlm",
            reason: "Insufficient memory"
        )

        XCTAssertTrue(result.isDisqualified)
        XCTAssertEqual(result.disqualificationReason, "Insufficient memory")
        XCTAssertEqual(result.score, 0)
        XCTAssertEqual(result.totalScore, 0)
        XCTAssertEqual(result.maxScore, 0)
        XCTAssertTrue(result.documentResults.isEmpty)
    }

    func testVLMBenchmarkResultEmptyDocuments() {
        let result = VLMBenchmarkResult.from(
            modelName: "test/vlm",
            documentResults: [],
            elapsedSeconds: 0
        )

        XCTAssertEqual(result.score, 0)
        XCTAssertEqual(result.totalScore, 0)
        XCTAssertEqual(result.maxScore, 0)
    }

    // MARK: - TextLLMDocumentResult

    func testTextLLMDocumentResultFullyCorrect() {
        let result = TextLLMDocumentResult(
            filename: "invoice.pdf",
            isPositiveSample: true,
            categorizationCorrect: true,
            extractionCorrect: true
        )
        XCTAssertEqual(result.score, 2)
    }

    func testTextLLMDocumentResultPartiallyCorrect() {
        let result = TextLLMDocumentResult(
            filename: "invoice.pdf",
            isPositiveSample: true,
            categorizationCorrect: true,
            extractionCorrect: false
        )
        XCTAssertEqual(result.score, 1)
    }

    func testTextLLMDocumentResultFullyWrong() {
        let result = TextLLMDocumentResult(
            filename: "invoice.pdf",
            isPositiveSample: true,
            categorizationCorrect: false,
            extractionCorrect: false
        )
        XCTAssertEqual(result.score, 0)
    }

    func testTextLLMDocumentResultCorrectNegativeRejection() {
        let result = TextLLMDocumentResult(
            filename: "not_invoice.pdf",
            isPositiveSample: false,
            categorizationCorrect: true,
            extractionCorrect: true
        )
        XCTAssertEqual(result.score, 2)
    }

    // MARK: - TextLLMBenchmarkResult

    func testTextLLMBenchmarkResultFromDocuments() {
        let results = [
            TextLLMDocumentResult(filename: "a.pdf", isPositiveSample: true,
                                  categorizationCorrect: true, extractionCorrect: true),
            TextLLMDocumentResult(filename: "b.pdf", isPositiveSample: true,
                                  categorizationCorrect: true, extractionCorrect: false),
            TextLLMDocumentResult(filename: "c.pdf", isPositiveSample: false,
                                  categorizationCorrect: false, extractionCorrect: false),
        ]
        let benchmarkResult = TextLLMBenchmarkResult.from(
            modelName: "test/text",
            documentResults: results,
            elapsedSeconds: 15.0
        )

        XCTAssertEqual(benchmarkResult.totalScore, 3) // 2 + 1 + 0
        XCTAssertEqual(benchmarkResult.maxScore, 6) // 2 * 3
        XCTAssertEqual(benchmarkResult.score, 0.5)
        XCTAssertEqual(benchmarkResult.fullyCorrectCount, 1)
        XCTAssertEqual(benchmarkResult.partiallyCorrectCount, 1)
        XCTAssertEqual(benchmarkResult.fullyWrongCount, 1)
        XCTAssertEqual(benchmarkResult.elapsedSeconds, 15.0)
    }

    func testTextLLMBenchmarkResultDisqualified() {
        let result = TextLLMBenchmarkResult.disqualified(
            modelName: "test/text",
            reason: "Failed to load"
        )

        XCTAssertTrue(result.isDisqualified)
        XCTAssertEqual(result.disqualificationReason, "Failed to load")
        XCTAssertEqual(result.score, 0)
    }

    func testTextLLMBenchmarkResultEmptyDocuments() {
        let result = TextLLMBenchmarkResult.from(
            modelName: "test/text",
            documentResults: [],
            elapsedSeconds: 0
        )

        XCTAssertEqual(result.score, 0)
        XCTAssertEqual(result.maxScore, 0)
    }
}
