@testable import DocScanCore
import XCTest

/// Extended tests for BenchmarkWorkerIO data structures: serialization, accessors, and factory methods.
final class BenchmarkWorkerIOExtendedTests: XCTestCase {
    // MARK: - BenchmarkPDFSet

    func testPDFSetCount() {
        let set = BenchmarkPDFSet(
            positivePDFs: ["/a.pdf", "/b.pdf"],
            negativePDFs: ["/c.pdf"],
        )
        XCTAssertEqual(set.count, 3)
    }

    func testPDFSetCountEmpty() {
        let set = BenchmarkPDFSet(positivePDFs: [], negativePDFs: [])
        XCTAssertEqual(set.count, 0)
    }

    func testPDFSetEquatable() {
        let set1 = BenchmarkPDFSet(positivePDFs: ["/a.pdf"], negativePDFs: ["/b.pdf"])
        let set2 = BenchmarkPDFSet(positivePDFs: ["/a.pdf"], negativePDFs: ["/b.pdf"])
        XCTAssertEqual(set1, set2)
    }

    func testPDFSetCodableRoundTrip() throws {
        let original = BenchmarkPDFSet(positivePDFs: ["/a.pdf"], negativePDFs: ["/b.pdf"])
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(BenchmarkPDFSet.self, from: data)
        XCTAssertEqual(original, decoded)
    }

    // MARK: - BenchmarkWorkerOutput accessors

    func testVLMResultAccessor() {
        let vlmResult = VLMBenchmarkResult.disqualified(modelName: "test", reason: "test")
        let output = BenchmarkWorkerOutput.vlm(vlmResult)

        XCTAssertNotNil(output.vlmResult)
        XCTAssertNil(output.textLLMResult)
        XCTAssertEqual(output.vlmResult?.modelName, "test")
    }

    func testTextLLMResultAccessor() {
        let textResult = TextLLMBenchmarkResult.disqualified(modelName: "test", reason: "test")
        let output = BenchmarkWorkerOutput.textLLM(textResult)

        XCTAssertNil(output.vlmResult)
        XCTAssertNotNil(output.textLLMResult)
        XCTAssertEqual(output.textLLMResult?.modelName, "test")
    }

    // MARK: - BenchmarkWorkerInput.makeDisqualifiedOutput

    func testMakeDisqualifiedOutputVLMPhase() {
        let input = BenchmarkWorkerInput(
            phase: .vlm,
            modelName: "test-vlm",
            pdfSet: BenchmarkPDFSet(positivePDFs: [], negativePDFs: []),
            timeoutSeconds: 10,
            documentType: .invoice,
            configuration: Configuration.defaultConfiguration,
        )

        let output = input.makeDisqualifiedOutput(reason: "crashed")
        if case let .vlm(result) = output {
            XCTAssertTrue(result.isDisqualified)
            XCTAssertEqual(result.disqualificationReason, "crashed")
            XCTAssertEqual(result.modelName, "test-vlm")
        } else {
            XCTFail("Expected VLM output")
        }
    }

    func testMakeDisqualifiedOutputTextLLMPhase() {
        let input = BenchmarkWorkerInput(
            phase: .textLLM,
            modelName: "test-text",
            pdfSet: BenchmarkPDFSet(positivePDFs: [], negativePDFs: []),
            timeoutSeconds: 10,
            documentType: .invoice,
            configuration: Configuration.defaultConfiguration,
        )

        let output = input.makeDisqualifiedOutput(reason: "OOM")
        if case let .textLLM(result) = output {
            XCTAssertTrue(result.isDisqualified)
            XCTAssertEqual(result.disqualificationReason, "OOM")
            XCTAssertEqual(result.modelName, "test-text")
        } else {
            XCTFail("Expected TextLLM output")
        }
    }

    // MARK: - BenchmarkWorkerOutput Codable round-trip

    func testWorkerOutputVLMCodableRoundTrip() throws {
        let vlmResult = VLMBenchmarkResult(
            modelName: "test",
            totalScore: 5,
            maxScore: 10,
            documentResults: [],
            elapsedSeconds: 1.5,
        )
        let original = BenchmarkWorkerOutput.vlm(vlmResult)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(BenchmarkWorkerOutput.self, from: data)
        XCTAssertEqual(original, decoded)
    }

    func testWorkerOutputTextLLMCodableRoundTrip() throws {
        let textResult = TextLLMBenchmarkResult(
            modelName: "test",
            totalScore: 8,
            maxScore: 16,
            documentResults: [],
            elapsedSeconds: 2.3,
        )
        let original = BenchmarkWorkerOutput.textLLM(textResult)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(BenchmarkWorkerOutput.self, from: data)
        XCTAssertEqual(original, decoded)
    }

    // MARK: - TextLLMInputData

    func testTextLLMInputDataCodableRoundTrip() throws {
        let gt = GroundTruth(isMatch: true, documentType: .invoice, date: "2025-01-15", secondaryField: "Acme")
        let original = TextLLMInputData(
            ocrTexts: ["/a.pdf": "invoice text"],
            groundTruths: ["/a.pdf": gt],
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(TextLLMInputData.self, from: data)
        XCTAssertEqual(original, decoded)
    }

    // MARK: - BenchmarkMetrics Factory Methods

    func testVLMBenchmarkResultFromDocumentResults() {
        let results = [
            VLMDocumentResult(filename: "a.pdf", isPositiveSample: true, predictedIsMatch: true),
            VLMDocumentResult(filename: "b.pdf", isPositiveSample: true, predictedIsMatch: false),
            VLMDocumentResult(filename: "c.pdf", isPositiveSample: false, predictedIsMatch: false),
        ]

        let benchmark = VLMBenchmarkResult.from(
            modelName: "test", documentResults: results, elapsedSeconds: 5.0,
        )

        XCTAssertEqual(benchmark.totalScore, 2) // TP + TN
        XCTAssertEqual(benchmark.maxScore, 3)
        XCTAssertEqual(benchmark.truePositives, 1)
        XCTAssertEqual(benchmark.trueNegatives, 1)
        XCTAssertEqual(benchmark.falseNegatives, 1)
        XCTAssertEqual(benchmark.falsePositives, 0)
        XCTAssertFalse(benchmark.isDisqualified)
    }

    func testTextLLMBenchmarkResultFromDocumentResults() {
        let results = [
            TextLLMDocumentResult(filename: "a.pdf", isPositiveSample: true, categorizationCorrect: true, extractionCorrect: true),
            TextLLMDocumentResult(filename: "b.pdf", isPositiveSample: true, categorizationCorrect: true, extractionCorrect: false),
            TextLLMDocumentResult(filename: "c.pdf", isPositiveSample: false, categorizationCorrect: false, extractionCorrect: false),
        ]

        let benchmark = TextLLMBenchmarkResult.from(
            modelName: "test", documentResults: results, elapsedSeconds: 3.0,
        )

        XCTAssertEqual(benchmark.totalScore, 3) // 2 + 1 + 0
        XCTAssertEqual(benchmark.maxScore, 6) // 2 * 3
        XCTAssertEqual(benchmark.fullyCorrectCount, 1)
        XCTAssertEqual(benchmark.partiallyCorrectCount, 1)
        XCTAssertEqual(benchmark.fullyWrongCount, 1)
        XCTAssertFalse(benchmark.isDisqualified)
    }

    func testVLMBenchmarkResultScoreZeroMaxScore() {
        let result = VLMBenchmarkResult(
            modelName: "test", totalScore: 0, maxScore: 0,
            documentResults: [], elapsedSeconds: 0,
        )
        XCTAssertEqual(result.score, 0.0)
    }

    func testTextLLMBenchmarkResultScoreZeroMaxScore() {
        let result = TextLLMBenchmarkResult(
            modelName: "test", totalScore: 0, maxScore: 0,
            documentResults: [], elapsedSeconds: 0,
        )
        XCTAssertEqual(result.score, 0.0)
    }

    // MARK: - VLMDocumentResult

    func testVLMDocumentResultTruePositive() {
        let result = VLMDocumentResult(filename: "a.pdf", isPositiveSample: true, predictedIsMatch: true)
        XCTAssertTrue(result.correct)
        XCTAssertEqual(result.score, 1)
    }

    func testVLMDocumentResultFalseNegative() {
        let result = VLMDocumentResult(filename: "a.pdf", isPositiveSample: true, predictedIsMatch: false)
        XCTAssertFalse(result.correct)
        XCTAssertEqual(result.score, 0)
    }

    func testVLMDocumentResultTrueNegative() {
        let result = VLMDocumentResult(filename: "a.pdf", isPositiveSample: false, predictedIsMatch: false)
        XCTAssertTrue(result.correct)
        XCTAssertEqual(result.score, 1)
    }

    func testVLMDocumentResultFalsePositive() {
        let result = VLMDocumentResult(filename: "a.pdf", isPositiveSample: false, predictedIsMatch: true)
        XCTAssertFalse(result.correct)
        XCTAssertEqual(result.score, 0)
    }

    // MARK: - TextLLMDocumentResult

    func testTextLLMDocumentResultBothCorrect() {
        let result = TextLLMDocumentResult(filename: "a.pdf", isPositiveSample: true, categorizationCorrect: true, extractionCorrect: true)
        XCTAssertEqual(result.score, 2)
    }

    func testTextLLMDocumentResultOneCorrect() {
        let result = TextLLMDocumentResult(filename: "a.pdf", isPositiveSample: true, categorizationCorrect: true, extractionCorrect: false)
        XCTAssertEqual(result.score, 1)
    }

    func testTextLLMDocumentResultBothWrong() {
        let result = TextLLMDocumentResult(filename: "a.pdf", isPositiveSample: true, categorizationCorrect: false, extractionCorrect: false)
        XCTAssertEqual(result.score, 0)
    }
}
