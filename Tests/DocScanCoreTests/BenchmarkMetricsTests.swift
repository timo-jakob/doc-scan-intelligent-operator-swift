@testable import DocScanCore
import XCTest

final class BenchmarkMetricsTests: XCTestCase {
    // MARK: - DocumentResult

    func testDocumentResultFullyCorrectPositive() {
        let result = DocumentResult(
            filename: "invoice.pdf",
            isPositiveSample: true,
            predictedIsMatch: true,
            documentScore: 2
        )
        XCTAssertTrue(result.isFullyCorrect)
        XCTAssertTrue(result.categorizationCorrect)
    }

    func testDocumentResultWrongCategorization() {
        let result = DocumentResult(
            filename: "invoice.pdf",
            isPositiveSample: true,
            predictedIsMatch: false,
            documentScore: 0
        )
        XCTAssertFalse(result.isFullyCorrect)
        XCTAssertFalse(result.categorizationCorrect)
    }

    func testDocumentResultPartiallyCorrect() {
        let result = DocumentResult(
            filename: "invoice.pdf",
            isPositiveSample: true,
            predictedIsMatch: true,
            documentScore: 1
        )
        XCTAssertFalse(result.isFullyCorrect)
        XCTAssertTrue(result.categorizationCorrect)
    }

    func testDocumentResultCorrectNegative() {
        let result = DocumentResult(
            filename: "not_invoice.pdf",
            isPositiveSample: false,
            predictedIsMatch: false,
            documentScore: 2
        )
        XCTAssertTrue(result.isFullyCorrect)
        XCTAssertTrue(result.categorizationCorrect)
    }

    // MARK: - Perfect Scores

    func testPerfectScores() {
        let results = [
            makeResult("a.pdf", positive: true, predicted: true, score: 2),
            makeResult("b.pdf", positive: true, predicted: true, score: 2),
            makeResult("c.pdf", positive: false, predicted: false, score: 2),
        ]
        let metrics = BenchmarkMetrics.compute(from: results)

        XCTAssertEqual(metrics.score, 1.0)
        XCTAssertEqual(metrics.totalScore, 6)
        XCTAssertEqual(metrics.maxScore, 6)
        XCTAssertEqual(metrics.documentCount, 3)
        XCTAssertTrue(metrics.hasNegativeSamples)
        XCTAssertEqual(metrics.fullyCorrectCount, 3)
        XCTAssertEqual(metrics.partiallyCorrectCount, 0)
        XCTAssertEqual(metrics.fullyWrongCount, 0)
    }

    // MARK: - All Wrong

    func testAllWrong() {
        let results = [
            makeResult("a.pdf", positive: true, predicted: false, score: 0),
            makeResult("b.pdf", positive: false, predicted: true, score: 0),
        ]
        let metrics = BenchmarkMetrics.compute(from: results)

        XCTAssertEqual(metrics.score, 0.0)
        XCTAssertEqual(metrics.totalScore, 0)
        XCTAssertEqual(metrics.maxScore, 4)
        XCTAssertEqual(metrics.fullyWrongCount, 2)
    }

    // MARK: - Mixed Results

    func testMixedResults() {
        let results = [
            makeResult("a.pdf", positive: true, predicted: true, score: 2),
            makeResult("b.pdf", positive: true, predicted: true, score: 2),
            makeResult("c.pdf", positive: true, predicted: true, score: 1), // partial
            makeResult("d.pdf", positive: false, predicted: true, score: 0), // FP
            makeResult("e.pdf", positive: true, predicted: false, score: 0), // FN
            makeResult("f.pdf", positive: false, predicted: false, score: 2),
            makeResult("g.pdf", positive: false, predicted: false, score: 2),
        ]
        let metrics = BenchmarkMetrics.compute(from: results)

        // totalScore = 2+2+1+0+0+2+2 = 9, maxScore = 14
        XCTAssertEqual(metrics.totalScore, 9)
        XCTAssertEqual(metrics.maxScore, 14)
        XCTAssertEqual(metrics.score, 9.0 / 14.0, accuracy: 0.001)
        XCTAssertEqual(metrics.documentCount, 7)
        XCTAssertTrue(metrics.hasNegativeSamples)
        XCTAssertEqual(metrics.fullyCorrectCount, 4)
        XCTAssertEqual(metrics.partiallyCorrectCount, 1)
        XCTAssertEqual(metrics.fullyWrongCount, 2)
    }

    // MARK: - No Negatives

    func testNoNegativeSamples() {
        let results = [
            makeResult("a.pdf", positive: true, predicted: true, score: 2),
            makeResult("b.pdf", positive: true, predicted: true, score: 2),
        ]
        let metrics = BenchmarkMetrics.compute(from: results)

        XCTAssertFalse(metrics.hasNegativeSamples)
        XCTAssertEqual(metrics.score, 1.0)
    }

    // MARK: - No Positives

    func testNoPositiveSamples() {
        let results = [
            makeResult("a.pdf", positive: false, predicted: false, score: 2),
            makeResult("b.pdf", positive: false, predicted: false, score: 2),
        ]
        let metrics = BenchmarkMetrics.compute(from: results)

        XCTAssertTrue(metrics.hasNegativeSamples)
        XCTAssertEqual(metrics.score, 1.0)
    }

    // MARK: - Single Document

    func testSingleFullyCorrect() {
        let results = [
            makeResult("a.pdf", positive: true, predicted: true, score: 2),
        ]
        let metrics = BenchmarkMetrics.compute(from: results)

        XCTAssertEqual(metrics.score, 1.0)
        XCTAssertEqual(metrics.totalScore, 2)
        XCTAssertEqual(metrics.maxScore, 2)
    }

    // MARK: - Empty Results

    func testEmptyResults() {
        let metrics = BenchmarkMetrics.compute(from: [])

        XCTAssertEqual(metrics.score, 0)
        XCTAssertEqual(metrics.totalScore, 0)
        XCTAssertEqual(metrics.maxScore, 0)
        XCTAssertEqual(metrics.documentCount, 0)
        XCTAssertFalse(metrics.hasNegativeSamples)
        XCTAssertEqual(metrics.fullyCorrectCount, 0)
        XCTAssertEqual(metrics.partiallyCorrectCount, 0)
        XCTAssertEqual(metrics.fullyWrongCount, 0)
    }

    // MARK: - ModelPairResult

    func testDisqualifiedPair() {
        let pair = ModelPairResult(
            vlmModelName: "vlm-model",
            textModelName: "text-model",
            metrics: BenchmarkMetrics.compute(from: []),
            documentResults: [],
            isDisqualified: true,
            disqualificationReason: "Exceeded timeout"
        )

        XCTAssertTrue(pair.isDisqualified)
        XCTAssertEqual(pair.disqualificationReason, "Exceeded timeout")
    }

    func testNonDisqualifiedPair() {
        let pair = ModelPairResult(
            vlmModelName: "vlm-model",
            textModelName: "text-model",
            metrics: BenchmarkMetrics.compute(from: []),
            documentResults: [],
            isDisqualified: false,
            disqualificationReason: nil
        )

        XCTAssertFalse(pair.isDisqualified)
        XCTAssertNil(pair.disqualificationReason)
    }

    // MARK: - Categorization Right but Extraction Wrong → Score 1

    func testCategorizationRightExtractionWrongGivesScore1() {
        let results = [
            makeResult("a.pdf", positive: true, predicted: true, score: 1),
        ]
        let metrics = BenchmarkMetrics.compute(from: results)

        XCTAssertEqual(metrics.score, 0.5)
        XCTAssertEqual(metrics.totalScore, 1)
        XCTAssertEqual(metrics.maxScore, 2)
        XCTAssertEqual(metrics.partiallyCorrectCount, 1)
        XCTAssertEqual(metrics.fullyCorrectCount, 0)
        XCTAssertEqual(metrics.fullyWrongCount, 0)
    }

    // MARK: - Helpers

    private func makeResult(
        _ filename: String,
        positive: Bool,
        predicted: Bool,
        score: Int
    ) -> DocumentResult {
        DocumentResult(
            filename: filename,
            isPositiveSample: positive,
            predictedIsMatch: predicted,
            documentScore: score
        )
    }
}
