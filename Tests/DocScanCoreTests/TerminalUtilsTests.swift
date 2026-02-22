@testable import DocScanCore
import XCTest

// Test the ModelPairResultRow and formatting logic
// Note: TerminalUtils is in the CLI target, so we test the data types
// and any formatting that can be tested via DocScanCore types

final class TerminalUtilsTests: XCTestCase {
    // MARK: - ModelPairResult to Row Conversion

    func testModelPairResultRowFromResult() {
        let metrics = BenchmarkMetrics.compute(from: [
            DocumentResult(filename: "a.pdf", isPositiveSample: true, predictedIsMatch: true, extractionCorrect: true),
            DocumentResult(filename: "b.pdf", isPositiveSample: false, predictedIsMatch: false, extractionCorrect: true),
        ])

        let result = ModelPairResult(
            vlmModelName: "test/vlm",
            textModelName: "test/text",
            metrics: metrics,
            documentResults: []
        )

        XCTAssertEqual(result.vlmModelName, "test/vlm")
        XCTAssertEqual(result.textModelName, "test/text")
        XCTAssertEqual(result.metrics.accuracy, 1.0)
        XCTAssertFalse(result.isDisqualified)
    }

    // MARK: - BenchmarkMetrics Table Data

    func testMetricsTableWithPerfectScores() {
        let results = [
            DocumentResult(filename: "a.pdf", isPositiveSample: true, predictedIsMatch: true, extractionCorrect: true),
            DocumentResult(filename: "b.pdf", isPositiveSample: false, predictedIsMatch: false, extractionCorrect: true),
        ]
        let metrics = BenchmarkMetrics.compute(from: results)

        XCTAssertEqual(metrics.accuracy, 1.0)
        XCTAssertEqual(metrics.precision, 1.0)
        XCTAssertEqual(metrics.recall, 1.0)
        XCTAssertEqual(metrics.f1Score, 1.0)
    }

    func testMetricsTableWithDisqualified() {
        let result = ModelPairResult(
            vlmModelName: "test/vlm",
            textModelName: "test/text",
            metrics: BenchmarkMetrics.compute(from: []),
            documentResults: [],
            isDisqualified: true,
            disqualificationReason: "Timeout exceeded"
        )

        XCTAssertTrue(result.isDisqualified)
        XCTAssertEqual(result.disqualificationReason, "Timeout exceeded")
    }

    func testMetricsWithNoNegativeSamples() {
        let results = [
            DocumentResult(filename: "a.pdf", isPositiveSample: true, predictedIsMatch: true, extractionCorrect: true),
        ]
        let metrics = BenchmarkMetrics.compute(from: results)

        XCTAssertFalse(metrics.hasNegativeSamples)
        XCTAssertEqual(metrics.accuracy, 1.0)
    }

    // MARK: - Leaderboard Sorting

    func testLeaderboardSortingByAccuracy() {
        let results = [
            makeResult(vlm: "low", accuracy: 0.5),
            makeResult(vlm: "high", accuracy: 0.9),
            makeResult(vlm: "mid", accuracy: 0.7),
        ]

        let sorted = results
            .sorted { $0.metrics.accuracy > $1.metrics.accuracy }

        XCTAssertEqual(sorted[0].vlmModelName, "high")
        XCTAssertEqual(sorted[1].vlmModelName, "mid")
        XCTAssertEqual(sorted[2].vlmModelName, "low")
    }

    func testLeaderboardExcludesDisqualified() {
        let results = [
            makeResult(vlm: "good", accuracy: 0.9),
            makeDisqualifiedResult(vlm: "dq"),
        ]

        let qualifying = results.filter { !$0.isDisqualified }
        XCTAssertEqual(qualifying.count, 1)
        XCTAssertEqual(qualifying[0].vlmModelName, "good")
    }

    // MARK: - Helpers

    private func makeResult(vlm: String, accuracy: Double) -> ModelPairResult {
        // Create DocumentResults that produce the desired accuracy
        var results: [DocumentResult] = []
        let total = 10
        let correct = Int(accuracy * Double(total))

        for i in 0 ..< total {
            results.append(DocumentResult(
                filename: "\(i).pdf",
                isPositiveSample: true,
                predictedIsMatch: true,
                extractionCorrect: i < correct
            ))
        }

        return ModelPairResult(
            vlmModelName: vlm,
            textModelName: "text",
            metrics: BenchmarkMetrics.compute(from: results),
            documentResults: results
        )
    }

    private func makeDisqualifiedResult(vlm: String) -> ModelPairResult {
        ModelPairResult(
            vlmModelName: vlm,
            textModelName: "text",
            metrics: BenchmarkMetrics.compute(from: []),
            documentResults: [],
            isDisqualified: true,
            disqualificationReason: "Timeout"
        )
    }
}
