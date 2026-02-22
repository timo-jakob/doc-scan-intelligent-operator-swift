@testable import DocScanCore
import XCTest

final class BenchmarkMetricsTests: XCTestCase {
    // MARK: - DocumentResult

    func testDocumentResultFullyCorrectPositive() {
        let result = DocumentResult(
            filename: "invoice.pdf",
            isPositiveSample: true,
            predictedIsMatch: true,
            extractionCorrect: true
        )
        XCTAssertTrue(result.isFullyCorrect)
    }

    func testDocumentResultWrongCategorization() {
        let result = DocumentResult(
            filename: "invoice.pdf",
            isPositiveSample: true,
            predictedIsMatch: false,
            extractionCorrect: true
        )
        XCTAssertFalse(result.isFullyCorrect)
    }

    func testDocumentResultWrongExtraction() {
        let result = DocumentResult(
            filename: "invoice.pdf",
            isPositiveSample: true,
            predictedIsMatch: true,
            extractionCorrect: false
        )
        XCTAssertFalse(result.isFullyCorrect)
    }

    func testDocumentResultCorrectNegative() {
        let result = DocumentResult(
            filename: "not_invoice.pdf",
            isPositiveSample: false,
            predictedIsMatch: false,
            extractionCorrect: true
        )
        XCTAssertTrue(result.isFullyCorrect)
    }

    // MARK: - Perfect Scores

    func testPerfectScores() {
        let results = [
            DocumentResult(filename: "a.pdf", isPositiveSample: true, predictedIsMatch: true, extractionCorrect: true),
            DocumentResult(filename: "b.pdf", isPositiveSample: true, predictedIsMatch: true, extractionCorrect: true),
            DocumentResult(filename: "c.pdf", isPositiveSample: false, predictedIsMatch: false, extractionCorrect: true),
        ]
        let metrics = BenchmarkMetrics.compute(from: results)

        XCTAssertEqual(metrics.accuracy, 1.0)
        XCTAssertEqual(metrics.precision, 1.0)
        XCTAssertEqual(metrics.recall, 1.0)
        XCTAssertEqual(metrics.f1Score, 1.0)
        XCTAssertTrue(metrics.hasNegativeSamples)
        XCTAssertEqual(metrics.truePositives, 2)
        XCTAssertEqual(metrics.trueNegatives, 1)
        XCTAssertEqual(metrics.falsePositives, 0)
        XCTAssertEqual(metrics.falseNegatives, 0)
    }

    // MARK: - All Wrong

    func testAllWrong() {
        let results = [
            DocumentResult(filename: "a.pdf", isPositiveSample: true, predictedIsMatch: false, extractionCorrect: false),
            DocumentResult(filename: "b.pdf", isPositiveSample: false, predictedIsMatch: true, extractionCorrect: false),
        ]
        let metrics = BenchmarkMetrics.compute(from: results)

        XCTAssertEqual(metrics.accuracy, 0.0)
        XCTAssertEqual(metrics.precision, 0.0)
        XCTAssertEqual(metrics.recall, 0.0)
    }

    // MARK: - Mixed Results

    func testMixedResults() {
        let results = [
            // 3 TP
            DocumentResult(filename: "a.pdf", isPositiveSample: true, predictedIsMatch: true, extractionCorrect: true),
            DocumentResult(filename: "b.pdf", isPositiveSample: true, predictedIsMatch: true, extractionCorrect: true),
            DocumentResult(filename: "c.pdf", isPositiveSample: true, predictedIsMatch: true, extractionCorrect: true),
            // 1 FP
            DocumentResult(filename: "d.pdf", isPositiveSample: false, predictedIsMatch: true, extractionCorrect: false),
            // 1 FN
            DocumentResult(filename: "e.pdf", isPositiveSample: true, predictedIsMatch: false, extractionCorrect: false),
            // 2 TN
            DocumentResult(filename: "f.pdf", isPositiveSample: false, predictedIsMatch: false, extractionCorrect: true),
            DocumentResult(filename: "g.pdf", isPositiveSample: false, predictedIsMatch: false, extractionCorrect: true),
        ]
        let metrics = BenchmarkMetrics.compute(from: results)

        XCTAssertEqual(metrics.truePositives, 3)
        XCTAssertEqual(metrics.falsePositives, 1)
        XCTAssertEqual(metrics.falseNegatives, 1)
        XCTAssertEqual(metrics.trueNegatives, 2)

        // accuracy = (3+2)/7
        XCTAssertEqual(metrics.accuracy, 5.0 / 7.0, accuracy: 0.001)
        // precision = 3/(3+1) = 0.75
        XCTAssertEqual(metrics.precision!, 0.75, accuracy: 0.001)
        // recall = 3/(3+1) = 0.75
        XCTAssertEqual(metrics.recall!, 0.75, accuracy: 0.001)
        // F1 = 2 * 0.75 * 0.75 / (0.75 + 0.75) = 0.75
        XCTAssertEqual(metrics.f1Score!, 0.75, accuracy: 0.001)
    }

    // MARK: - No Negatives

    func testNoNegativeSamples() {
        let results = [
            DocumentResult(filename: "a.pdf", isPositiveSample: true, predictedIsMatch: true, extractionCorrect: true),
            DocumentResult(filename: "b.pdf", isPositiveSample: true, predictedIsMatch: true, extractionCorrect: true),
        ]
        let metrics = BenchmarkMetrics.compute(from: results)

        XCTAssertFalse(metrics.hasNegativeSamples)
        XCTAssertEqual(metrics.accuracy, 1.0)
        XCTAssertEqual(metrics.recall, 1.0)
        // precision = 2/(2+0) = 1.0
        XCTAssertEqual(metrics.precision, 1.0)
    }

    // MARK: - No Positives

    func testNoPositiveSamples() {
        let results = [
            DocumentResult(filename: "a.pdf", isPositiveSample: false, predictedIsMatch: false, extractionCorrect: true),
            DocumentResult(filename: "b.pdf", isPositiveSample: false, predictedIsMatch: false, extractionCorrect: true),
        ]
        let metrics = BenchmarkMetrics.compute(from: results)

        XCTAssertTrue(metrics.hasNegativeSamples)
        XCTAssertEqual(metrics.accuracy, 1.0)
        // recall is nil (no actual positives: TP+FN = 0)
        XCTAssertNil(metrics.recall)
        // precision is nil (no predicted positives: TP+FP = 0)
        XCTAssertNil(metrics.precision)
        XCTAssertNil(metrics.f1Score)
    }

    // MARK: - Single Document

    func testSingleTruePositive() {
        let results = [
            DocumentResult(filename: "a.pdf", isPositiveSample: true, predictedIsMatch: true, extractionCorrect: true),
        ]
        let metrics = BenchmarkMetrics.compute(from: results)

        XCTAssertEqual(metrics.accuracy, 1.0)
        XCTAssertEqual(metrics.recall, 1.0)
    }

    // MARK: - Empty Results

    func testEmptyResults() {
        let metrics = BenchmarkMetrics.compute(from: [])

        XCTAssertEqual(metrics.accuracy, 0)
        XCTAssertNil(metrics.precision)
        XCTAssertNil(metrics.recall)
        XCTAssertNil(metrics.f1Score)
        XCTAssertFalse(metrics.hasNegativeSamples)
        XCTAssertEqual(metrics.truePositives, 0)
        XCTAssertEqual(metrics.falsePositives, 0)
        XCTAssertEqual(metrics.trueNegatives, 0)
        XCTAssertEqual(metrics.falseNegatives, 0)
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

    // MARK: - Extraction Wrong but Categorization Right

    func testExtractionWrongCountsAsFalseNegative() {
        let results = [
            // Positive sample, correctly categorized but extraction wrong -> FN
            DocumentResult(filename: "a.pdf", isPositiveSample: true, predictedIsMatch: true, extractionCorrect: false),
        ]
        let metrics = BenchmarkMetrics.compute(from: results)

        XCTAssertEqual(metrics.truePositives, 0)
        XCTAssertEqual(metrics.falseNegatives, 1)
        XCTAssertEqual(metrics.accuracy, 0.0)
    }
}
