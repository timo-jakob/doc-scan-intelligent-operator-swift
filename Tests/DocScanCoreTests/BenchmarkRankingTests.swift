@testable import DocScanCore
import XCTest

final class BenchmarkRankingTests: XCTestCase {
    func testRankedByScoreOrdersByScoreDescending() {
        let low = VLMBenchmarkResult.from(
            modelName: "low",
            documentResults: [
                VLMDocumentResult(filename: "a.pdf", isPositiveSample: true, predictedIsMatch: false),
                VLMDocumentResult(filename: "b.pdf", isPositiveSample: false, predictedIsMatch: false),
            ],
            elapsedSeconds: 5.0
        ) // 1/2 = 50%
        let high = VLMBenchmarkResult.from(
            modelName: "high",
            documentResults: [
                VLMDocumentResult(filename: "a.pdf", isPositiveSample: true, predictedIsMatch: true),
                VLMDocumentResult(filename: "b.pdf", isPositiveSample: false, predictedIsMatch: false),
            ],
            elapsedSeconds: 10.0
        ) // 2/2 = 100%

        let ranked = [low, high].rankedByScore()

        XCTAssertEqual(ranked.map(\.modelName), ["high", "low"])
    }

    func testRankedByScoreBreaksTieByElapsedTime() {
        let slow = VLMBenchmarkResult.from(
            modelName: "slow",
            documentResults: [
                VLMDocumentResult(filename: "a.pdf", isPositiveSample: true, predictedIsMatch: true),
            ],
            elapsedSeconds: 10.0
        )
        let fast = VLMBenchmarkResult.from(
            modelName: "fast",
            documentResults: [
                VLMDocumentResult(filename: "a.pdf", isPositiveSample: true, predictedIsMatch: true),
            ],
            elapsedSeconds: 2.0
        )

        let ranked = [slow, fast].rankedByScore()

        XCTAssertEqual(ranked.map(\.modelName), ["fast", "slow"])
    }

    func testRankedByScoreFiltersDisqualified() {
        let good = VLMBenchmarkResult.from(
            modelName: "good",
            documentResults: [
                VLMDocumentResult(filename: "a.pdf", isPositiveSample: true, predictedIsMatch: true),
            ],
            elapsedSeconds: 5.0
        )
        let disqualified = VLMBenchmarkResult.disqualified(
            modelName: "bad", reason: "crashed"
        )

        let ranked = [disqualified, good].rankedByScore()

        XCTAssertEqual(ranked.count, 1)
        XCTAssertEqual(ranked.first?.modelName, "good")
    }

    func testRankedByScoreEmptyArray() {
        let ranked = [VLMBenchmarkResult]().rankedByScore()

        XCTAssertTrue(ranked.isEmpty)
    }

    func testRankedByScoreAllDisqualified() {
        let results = [
            VLMBenchmarkResult.disqualified(modelName: "a", reason: "crash"),
            VLMBenchmarkResult.disqualified(modelName: "b", reason: "timeout"),
        ]

        let ranked = results.rankedByScore()

        XCTAssertTrue(ranked.isEmpty)
    }
}
