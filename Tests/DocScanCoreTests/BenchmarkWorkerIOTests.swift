@testable import DocScanCore
import XCTest

final class BenchmarkWorkerIOTests: XCTestCase {
    // MARK: - BenchmarkWorkerInput Round-Trip (VLM)

    func testVLMInputCodableRoundTrip() throws {
        var config = Configuration.defaultConfiguration
        config.verbose = true
        let input = BenchmarkWorkerInput(
            phase: .vlm,
            modelName: "mlx-community/Qwen2-VL-2B-Instruct-4bit",
            pdfSet: BenchmarkPDFSet(
                positivePDFs: ["/path/to/invoice1.pdf", "/path/to/invoice2.pdf"],
                negativePDFs: ["/path/to/not_invoice.pdf"]
            ),
            timeoutSeconds: 30.0,
            documentType: .invoice,
            configuration: config
        )

        let data = try JSONEncoder().encode(input)
        let decoded = try JSONDecoder().decode(BenchmarkWorkerInput.self, from: data)

        XCTAssertEqual(decoded.phase, .vlm)
        XCTAssertEqual(decoded.modelName, input.modelName)
        XCTAssertEqual(decoded.pdfSet.positivePDFs, input.pdfSet.positivePDFs)
        XCTAssertEqual(decoded.pdfSet.negativePDFs, input.pdfSet.negativePDFs)
        XCTAssertEqual(decoded.timeoutSeconds, input.timeoutSeconds)
        XCTAssertEqual(decoded.documentType, .invoice)
        XCTAssertEqual(decoded.configuration.verbose, true)
        XCTAssertNil(decoded.textLLMData)
    }

    // MARK: - BenchmarkWorkerInput Round-Trip (TextLLM)

    func testTextLLMInputCodableRoundTrip() throws {
        let groundTruth = GroundTruth(
            isMatch: true,
            documentType: .invoice,
            date: "2025-01-15",
            secondaryField: "Test_Company"
        )

        let input = BenchmarkWorkerInput(
            phase: .textLLM,
            modelName: "mlx-community/Qwen2.5-7B-Instruct-4bit",
            pdfSet: BenchmarkPDFSet(
                positivePDFs: ["/path/to/invoice.pdf"],
                negativePDFs: ["/path/to/other.pdf"]
            ),
            timeoutSeconds: 60.0,
            documentType: .invoice,
            configuration: Configuration.defaultConfiguration,
            textLLMData: TextLLMInputData(
                ocrTexts: ["/path/to/invoice.pdf": "Rechnung Nr. 12345"],
                groundTruths: ["/path/to/invoice.pdf": groundTruth]
            )
        )

        let data = try JSONEncoder().encode(input)
        let decoded = try JSONDecoder().decode(BenchmarkWorkerInput.self, from: data)

        XCTAssertEqual(decoded.phase, .textLLM)
        XCTAssertEqual(decoded.modelName, input.modelName)
        XCTAssertEqual(decoded.textLLMData?.ocrTexts["/path/to/invoice.pdf"], "Rechnung Nr. 12345")
        XCTAssertEqual(decoded.textLLMData?.groundTruths["/path/to/invoice.pdf"]?.date, "2025-01-15")
        XCTAssertEqual(decoded.textLLMData?.groundTruths["/path/to/invoice.pdf"]?.secondaryField, "Test_Company")
    }

    // MARK: - BenchmarkWorkerOutput Round-Trip (VLM)

    func testVLMOutputCodableRoundTrip() throws {
        let vlmResult = VLMBenchmarkResult.from(
            modelName: "test/vlm",
            documentResults: [
                VLMDocumentResult(filename: "a.pdf", isPositiveSample: true, predictedIsMatch: true),
                VLMDocumentResult(filename: "b.pdf", isPositiveSample: false, predictedIsMatch: false),
            ],
            elapsedSeconds: 5.0
        )
        let output = BenchmarkWorkerOutput.vlm(vlmResult)

        let data = try JSONEncoder().encode(output)
        let decoded = try JSONDecoder().decode(BenchmarkWorkerOutput.self, from: data)

        XCTAssertNotNil(decoded.vlmResult)
        XCTAssertNil(decoded.textLLMResult)
        XCTAssertEqual(decoded.vlmResult?.modelName, "test/vlm")
        XCTAssertEqual(decoded.vlmResult?.totalScore, 2)
        XCTAssertEqual(decoded.vlmResult?.maxScore, 2)
        XCTAssertEqual(decoded.vlmResult?.elapsedSeconds, 5.0)
        XCTAssertEqual(decoded.vlmResult?.documentResults.count, 2)
    }

    // MARK: - BenchmarkWorkerOutput Round-Trip (TextLLM)

    func testTextLLMOutputCodableRoundTrip() throws {
        let textResult = TextLLMBenchmarkResult.from(
            modelName: "test/text",
            documentResults: [
                TextLLMDocumentResult(
                    filename: "a.pdf", isPositiveSample: true,
                    categorizationCorrect: true, extractionCorrect: true
                ),
            ],
            elapsedSeconds: 12.0
        )
        let output = BenchmarkWorkerOutput.textLLM(textResult)

        let data = try JSONEncoder().encode(output)
        let decoded = try JSONDecoder().decode(BenchmarkWorkerOutput.self, from: data)

        XCTAssertNil(decoded.vlmResult)
        XCTAssertNotNil(decoded.textLLMResult)
        XCTAssertEqual(decoded.textLLMResult?.modelName, "test/text")
        XCTAssertEqual(decoded.textLLMResult?.totalScore, 2)
        XCTAssertEqual(decoded.textLLMResult?.elapsedSeconds, 12.0)
    }

    // MARK: - BenchmarkWorkerOutput Disqualified Round-Trip

    func testDisqualifiedOutputCodableRoundTrip() throws {
        let vlmResult = VLMBenchmarkResult.disqualified(
            modelName: "bad/model", reason: "Worker crashed (signal 6)"
        )
        let output = BenchmarkWorkerOutput.vlm(vlmResult)

        let data = try JSONEncoder().encode(output)
        let decoded = try JSONDecoder().decode(BenchmarkWorkerOutput.self, from: data)

        XCTAssertTrue(decoded.vlmResult?.isDisqualified ?? false)
        XCTAssertEqual(decoded.vlmResult?.disqualificationReason, "Worker crashed (signal 6)")
    }

    // MARK: - BenchmarkWorkerPhase

    func testPhaseCodableRoundTrip() throws {
        for phase in [BenchmarkWorkerPhase.vlm, .textLLM] {
            let data = try JSONEncoder().encode(phase)
            let decoded = try JSONDecoder().decode(BenchmarkWorkerPhase.self, from: data)
            XCTAssertEqual(decoded, phase)
        }
    }

    // MARK: - Prescription Document Type Round-Trip

    func testPrescriptionInputCodableRoundTrip() throws {
        let input = BenchmarkWorkerInput(
            phase: .vlm,
            modelName: "test/model",
            pdfSet: BenchmarkPDFSet(positivePDFs: ["/rx.pdf"], negativePDFs: []),
            timeoutSeconds: 10.0,
            documentType: .prescription,
            configuration: Configuration.defaultConfiguration
        )

        let data = try JSONEncoder().encode(input)
        let decoded = try JSONDecoder().decode(BenchmarkWorkerInput.self, from: data)

        XCTAssertEqual(decoded.documentType, .prescription)
    }
}
