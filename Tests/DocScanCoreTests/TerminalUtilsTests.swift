@testable import DocScanCore
import XCTest

final class TerminalUtilsTests: XCTestCase {
    // MARK: - VLM Leaderboard Sorting

    func testVLMResultsSortByScoreDescending() {
        let results = [
            makeVLMResult(model: "low/vlm", score: 0.5, elapsed: 10),
            makeVLMResult(model: "high/vlm", score: 1.0, elapsed: 20),
            makeVLMResult(model: "mid/vlm", score: 0.75, elapsed: 15),
        ]

        let sorted = results
            .filter { !$0.isDisqualified }
            .sorted { lhs, rhs in
                if lhs.score != rhs.score { return lhs.score > rhs.score }
                return lhs.elapsedSeconds < rhs.elapsedSeconds
            }

        XCTAssertEqual(sorted[0].modelName, "high/vlm")
        XCTAssertEqual(sorted[1].modelName, "mid/vlm")
        XCTAssertEqual(sorted[2].modelName, "low/vlm")
    }

    func testVLMResultsSortBreaksTiesByTime() {
        let results = [
            makeVLMResult(model: "slow/vlm", score: 0.8, elapsed: 30),
            makeVLMResult(model: "fast/vlm", score: 0.8, elapsed: 10),
        ]

        let sorted = results
            .sorted { lhs, rhs in
                if lhs.score != rhs.score { return lhs.score > rhs.score }
                return lhs.elapsedSeconds < rhs.elapsedSeconds
            }

        XCTAssertEqual(sorted[0].modelName, "fast/vlm")
        XCTAssertEqual(sorted[1].modelName, "slow/vlm")
    }

    func testVLMDisqualifiedExcludedFromRanking() {
        let results: [VLMBenchmarkResult] = [
            makeVLMResult(model: "good/vlm", score: 1.0, elapsed: 10),
            VLMBenchmarkResult.disqualified(modelName: "bad/vlm", reason: "Out of memory"),
        ]

        let qualifying = results.filter { !$0.isDisqualified }
        XCTAssertEqual(qualifying.count, 1)
        XCTAssertEqual(qualifying[0].modelName, "good/vlm")
    }

    // MARK: - TextLLM Leaderboard Sorting

    func testTextLLMResultsSortByScoreDescending() {
        let results = [
            makeTextLLMResult(model: "low/text", score: 0.3, elapsed: 10),
            makeTextLLMResult(model: "high/text", score: 0.9, elapsed: 20),
        ]

        let sorted = results
            .filter { !$0.isDisqualified }
            .sorted { lhs, rhs in
                if lhs.score != rhs.score { return lhs.score > rhs.score }
                return lhs.elapsedSeconds < rhs.elapsedSeconds
            }

        XCTAssertEqual(sorted[0].modelName, "high/text")
        XCTAssertEqual(sorted[1].modelName, "low/text")
    }

    func testTextLLMDisqualifiedExcludedFromRanking() {
        let results: [TextLLMBenchmarkResult] = [
            makeTextLLMResult(model: "good/text", score: 0.8, elapsed: 10),
            TextLLMBenchmarkResult.disqualified(modelName: "bad/text", reason: "Timeout"),
        ]

        let qualifying = results.filter { !$0.isDisqualified }
        XCTAssertEqual(qualifying.count, 1)
        XCTAssertEqual(qualifying[0].modelName, "good/text")
    }

    // MARK: - VLM Result Properties

    func testVLMResultTPTNFPFNCounts() {
        let docResults = [
            VLMDocumentResult(filename: "a.pdf", isPositiveSample: true, predictedIsMatch: true), // TP
            VLMDocumentResult(filename: "b.pdf", isPositiveSample: false, predictedIsMatch: false), // TN
            VLMDocumentResult(filename: "c.pdf", isPositiveSample: false, predictedIsMatch: true), // FP
            VLMDocumentResult(filename: "d.pdf", isPositiveSample: true, predictedIsMatch: false), // FN
        ]
        let result = VLMBenchmarkResult.from(
            modelName: "test/vlm", documentResults: docResults, elapsedSeconds: 5
        )

        XCTAssertEqual(result.truePositives, 1)
        XCTAssertEqual(result.trueNegatives, 1)
        XCTAssertEqual(result.falsePositives, 1)
        XCTAssertEqual(result.falseNegatives, 1)
    }

    // MARK: - TextLLM Result Properties

    func testTextLLMResultScoreBreakdown() {
        let docResults = [
            TextLLMDocumentResult(filename: "a.pdf", isPositiveSample: true,
                                  categorizationCorrect: true, extractionCorrect: true), // 2
            TextLLMDocumentResult(filename: "b.pdf", isPositiveSample: true,
                                  categorizationCorrect: true, extractionCorrect: false), // 1
            TextLLMDocumentResult(filename: "c.pdf", isPositiveSample: true,
                                  categorizationCorrect: false, extractionCorrect: false), // 0
        ]
        let result = TextLLMBenchmarkResult.from(
            modelName: "test/text", documentResults: docResults, elapsedSeconds: 10
        )

        XCTAssertEqual(result.fullyCorrectCount, 1)
        XCTAssertEqual(result.partiallyCorrectCount, 1)
        XCTAssertEqual(result.fullyWrongCount, 1)
        XCTAssertEqual(result.totalScore, 3)
        XCTAssertEqual(result.maxScore, 6)
    }

    // MARK: - Elapsed Time

    func testElapsedTimePreserved() {
        let vlmResult = VLMBenchmarkResult.from(
            modelName: "vlm", documentResults: [], elapsedSeconds: 42.5
        )
        XCTAssertEqual(vlmResult.elapsedSeconds, 42.5)

        let textResult = TextLLMBenchmarkResult.from(
            modelName: "text", documentResults: [], elapsedSeconds: 99.9
        )
        XCTAssertEqual(textResult.elapsedSeconds, 99.9)
    }

    // MARK: - Helpers

    private func makeVLMResult(model: String, score: Double, elapsed: TimeInterval) -> VLMBenchmarkResult {
        let total = 10
        let correctCount = Int(score * Double(total))
        var results: [VLMDocumentResult] = []

        for index in 0 ..< total {
            let predictCorrect = index < correctCount
            results.append(VLMDocumentResult(
                filename: "\(index).pdf",
                isPositiveSample: true,
                predictedIsMatch: predictCorrect
            ))
        }

        return VLMBenchmarkResult.from(
            modelName: model,
            documentResults: results,
            elapsedSeconds: elapsed
        )
    }

    private func makeTextLLMResult(model: String, score: Double, elapsed: TimeInterval) -> TextLLMBenchmarkResult {
        let total = 10
        let targetScore = Int(score * Double(total) * 2)
        var results: [TextLLMDocumentResult] = []
        var remaining = targetScore

        for index in 0 ..< total {
            let docScore: Int
            if remaining >= 2 {
                docScore = 2
                remaining -= 2
            } else if remaining >= 1 {
                docScore = 1
                remaining -= 1
            } else {
                docScore = 0
            }

            results.append(TextLLMDocumentResult(
                filename: "\(index).pdf",
                isPositiveSample: true,
                categorizationCorrect: docScore >= 1,
                extractionCorrect: docScore >= 2
            ))
        }

        return TextLLMBenchmarkResult.from(
            modelName: model,
            documentResults: results,
            elapsedSeconds: elapsed
        )
    }
}
