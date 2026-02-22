@testable import DocScanCore
import XCTest

// Test the ModelPairResultRow and formatting logic
// Note: TerminalUtils is in the CLI target, so we test the data types
// and any formatting that can be tested via DocScanCore types

final class TerminalUtilsTests: XCTestCase {
    // MARK: - ModelPairResult to Row Conversion

    func testModelPairResultRowFromResult() {
        let metrics = BenchmarkMetrics.compute(from: [
            DocumentResult(
                filename: "a.pdf", isPositiveSample: true,
                predictedIsMatch: true, documentScore: 2
            ),
            DocumentResult(
                filename: "b.pdf", isPositiveSample: false,
                predictedIsMatch: false, documentScore: 2
            ),
        ])

        let result = ModelPairResult(
            vlmModelName: "test/vlm",
            textModelName: "test/text",
            metrics: metrics,
            documentResults: []
        )

        XCTAssertEqual(result.vlmModelName, "test/vlm")
        XCTAssertEqual(result.textModelName, "test/text")
        XCTAssertEqual(result.metrics.score, 1.0)
        XCTAssertFalse(result.isDisqualified)
    }

    // MARK: - BenchmarkMetrics Table Data

    func testMetricsTableWithPerfectScores() {
        let results = [
            DocumentResult(
                filename: "a.pdf", isPositiveSample: true,
                predictedIsMatch: true, documentScore: 2
            ),
            DocumentResult(
                filename: "b.pdf", isPositiveSample: false,
                predictedIsMatch: false, documentScore: 2
            ),
        ]
        let metrics = BenchmarkMetrics.compute(from: results)

        XCTAssertEqual(metrics.score, 1.0)
        XCTAssertEqual(metrics.totalScore, 4)
        XCTAssertEqual(metrics.maxScore, 4)
        XCTAssertEqual(metrics.fullyCorrectCount, 2)
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
            DocumentResult(filename: "a.pdf", isPositiveSample: true, predictedIsMatch: true, documentScore: 2),
        ]
        let metrics = BenchmarkMetrics.compute(from: results)

        XCTAssertFalse(metrics.hasNegativeSamples)
        XCTAssertEqual(metrics.score, 1.0)
    }

    // MARK: - Leaderboard Sorting

    func testLeaderboardSortingByScore() {
        let results = [
            makeResult(vlm: "low", score: 0.5),
            makeResult(vlm: "high", score: 0.9),
            makeResult(vlm: "mid", score: 0.7),
        ]

        let sorted = results
            .sorted { $0.metrics.score > $1.metrics.score }

        XCTAssertEqual(sorted[0].vlmModelName, "high")
        XCTAssertEqual(sorted[1].vlmModelName, "mid")
        XCTAssertEqual(sorted[2].vlmModelName, "low")
    }

    func testLeaderboardExcludesDisqualified() {
        let results = [
            makeResult(vlm: "good", score: 0.9),
            makeDisqualifiedResult(vlm: "dq"),
        ]

        let qualifying = results.filter { !$0.isDisqualified }
        XCTAssertEqual(qualifying.count, 1)
        XCTAssertEqual(qualifying[0].vlmModelName, "good")
    }

    // MARK: - Helpers

    private func makeResult(vlm: String, score: Double) -> ModelPairResult {
        // Create DocumentResults that produce the desired score
        var results: [DocumentResult] = []
        let total = 10
        let targetTotalScore = Int(score * Double(total) * 2)

        // Fill with score-2 docs first, then score-0
        let fullCorrect = targetTotalScore / 2
        let remainder = targetTotalScore % 2

        for index in 0 ..< total {
            let docScore = if index < fullCorrect {
                2
            } else if index == fullCorrect, remainder > 0 {
                1
            } else {
                0
            }
            results.append(DocumentResult(
                filename: "\(index).pdf",
                isPositiveSample: true,
                predictedIsMatch: true,
                documentScore: docScore
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
