import AppKit
import CoreGraphics
import CoreText
@testable import DocScanCore
import PDFKit
import XCTest

// MARK: - Skip Paths & Negative Directory Tests

extension BenchmarkEngineTests {
    func testRunInitialBenchmarkSkipsExistingSidecars() async throws {
        let pdf1 = positiveDir.appendingPathComponent("invoice1.pdf")
        let pdf2 = positiveDir.appendingPathComponent("invoice2.pdf")
        createTestPDF(at: pdf1)
        createTestPDF(at: pdf2)

        // Pre-create a sidecar for pdf1
        let groundTruth = GroundTruth(
            isMatch: true, documentType: .invoice,
            date: "2025-01-15", secondaryField: "Existing_Company"
        )
        try groundTruth.save(to: GroundTruth.sidecarPath(for: pdf1.path))

        let factory = MockDocumentDetectorFactory()
        factory.mockVLMResponse = "YES"
        factory.mockDate = DateUtils.parseDate("2025-06-27")
        factory.mockSecondaryField = "New_Company"

        let config = Configuration()
        let engine = BenchmarkEngine(
            configuration: config, documentType: .invoice, detectorFactory: factory
        )

        let results = try await engine.runInitialBenchmark(
            positiveDir: positiveDir.path,
            negativeDir: nil,
            skipPaths: Set([pdf1.path])
        )

        let first = try XCTUnwrap(results.first)
        XCTAssertEqual(first.documentResults.count, 2)

        // pdf1 was skipped — result uses existing sidecar (isMatch=true, extractionCorrect=true)
        let skipped = first.documentResults.first { $0.filename == "invoice1.pdf" }
        XCTAssertNotNil(skipped)
        XCTAssertTrue(try XCTUnwrap(skipped?.predictedIsMatch))
        XCTAssertTrue(try XCTUnwrap(skipped?.extractionCorrect))

        // pdf2 was processed normally — detector was called
        let processed = first.documentResults.first { $0.filename == "invoice2.pdf" }
        XCTAssertNotNil(processed)

        // Only 1 detector created (for pdf2), not 2
        XCTAssertEqual(factory.detectorsCreated, 1)
    }

    func testRunInitialBenchmarkSkipAllPaths() async throws {
        let pdf1 = positiveDir.appendingPathComponent("a.pdf")
        let pdf2 = positiveDir.appendingPathComponent("b.pdf")
        createTestPDF(at: pdf1)
        createTestPDF(at: pdf2)

        let groundTruthA = GroundTruth(isMatch: true, documentType: .invoice, date: "2025-01-01")
        let groundTruthB = GroundTruth(isMatch: false, documentType: .invoice)
        try groundTruthA.save(to: GroundTruth.sidecarPath(for: pdf1.path))
        try groundTruthB.save(to: GroundTruth.sidecarPath(for: pdf2.path))

        let factory = MockDocumentDetectorFactory()
        let config = Configuration()
        let engine = BenchmarkEngine(
            configuration: config, documentType: .invoice, detectorFactory: factory
        )

        let results = try await engine.runInitialBenchmark(
            positiveDir: positiveDir.path,
            negativeDir: nil,
            skipPaths: Set([pdf1.path, pdf2.path])
        )

        let first = try XCTUnwrap(results.first)
        XCTAssertEqual(first.documentResults.count, 2)

        // No detectors created at all
        XCTAssertEqual(factory.detectorsCreated, 0)

        // pdf1 sidecar had isMatch=true
        let resultA = first.documentResults.first { $0.filename == "a.pdf" }
        XCTAssertTrue(try XCTUnwrap(resultA?.predictedIsMatch))

        // pdf2 sidecar had isMatch=false
        let resultB = first.documentResults.first { $0.filename == "b.pdf" }
        XCTAssertFalse(try XCTUnwrap(resultB?.predictedIsMatch))
    }

    func testRunInitialBenchmarkEmptySkipPaths() async throws {
        let pdf1 = positiveDir.appendingPathComponent("invoice.pdf")
        createTestPDF(at: pdf1)

        let factory = MockDocumentDetectorFactory()
        factory.mockVLMResponse = "YES"
        factory.mockDate = DateUtils.parseDate("2025-06-27")
        factory.mockSecondaryField = "Test_Company"

        let config = Configuration()
        let engine = BenchmarkEngine(
            configuration: config, documentType: .invoice, detectorFactory: factory
        )

        // Default empty skipPaths — all documents processed normally
        let results = try await engine.runInitialBenchmark(
            positiveDir: positiveDir.path,
            negativeDir: nil
        )

        let first = try XCTUnwrap(results.first)
        XCTAssertEqual(first.documentResults.count, 1)
        XCTAssertEqual(factory.detectorsCreated, 1)
    }

    func testRunInitialBenchmarkSkipPathNotInCorpus() async throws {
        let pdf1 = positiveDir.appendingPathComponent("invoice.pdf")
        createTestPDF(at: pdf1)

        let factory = MockDocumentDetectorFactory()
        factory.mockVLMResponse = "YES"
        factory.mockDate = DateUtils.parseDate("2025-06-27")
        factory.mockSecondaryField = "Test_Company"

        let config = Configuration()
        let engine = BenchmarkEngine(
            configuration: config, documentType: .invoice, detectorFactory: factory
        )

        // skipPaths contains a path not in the corpus — should be ignored
        let results = try await engine.runInitialBenchmark(
            positiveDir: positiveDir.path,
            negativeDir: nil,
            skipPaths: Set(["/nonexistent/fake.pdf"])
        )

        let first = try XCTUnwrap(results.first)
        XCTAssertEqual(first.documentResults.count, 1)
        XCTAssertEqual(factory.detectorsCreated, 1)
    }

    func testBenchmarkWithNegativeDirectory() async throws {
        let posPDF = positiveDir.appendingPathComponent("invoice.pdf")
        let negPDF = negativeDir.appendingPathComponent("not_invoice.pdf")
        createTestPDF(at: posPDF)
        createTestPDF(at: negPDF, text: "Lorem ipsum dolor sit amet")

        let posGT = GroundTruth(
            isMatch: true, documentType: .invoice,
            date: "2025-01-01", secondaryField: "Company"
        )
        let negGT = GroundTruth(isMatch: false, documentType: .invoice)

        let factory = MockDocumentDetectorFactory()
        factory.mockVLMResponse = "NO"

        let config = Configuration()
        let engine = BenchmarkEngine(
            configuration: config,
            documentType: .invoice,
            detectorFactory: factory
        )

        let pair = ModelPair(vlmModelName: config.modelName, textModelName: config.textModelName)
        let groundTruths = [posPDF.path: posGT, negPDF.path: negGT]
        let result = try await engine.benchmarkModelPair(
            pair,
            pdfPaths: [posPDF.path, negPDF.path],
            groundTruths: groundTruths,
            timeoutSeconds: 30
        )

        // VLM says NO for both: positive=FN, negative=TN
        XCTAssertEqual(result.metrics.trueNegatives, 1)
        XCTAssertEqual(result.metrics.falseNegatives, 1)
        XCTAssertTrue(result.metrics.hasNegativeSamples)
    }
}
