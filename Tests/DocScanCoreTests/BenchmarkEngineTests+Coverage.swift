import AppKit
import CoreGraphics
import CoreText
@testable import DocScanCore
import XCTest

// MARK: - Coverage Tests for Benchmark Progress, Cleanup & Memory

extension BenchmarkEngineTests {
    // MARK: - Benchmark: Skip Documents Without Ground Truth

    func testBenchmarkSkipsDocumentWithoutGroundTruth() async throws {
        let pdf1 = positiveDir.appendingPathComponent("invoice.pdf")
        let pdf2 = positiveDir.appendingPathComponent("unknown.pdf")
        createTestPDF(at: pdf1)
        createTestPDF(at: pdf2)

        let groundTruth = GroundTruth(
            isMatch: true, documentType: .invoice,
            date: "2025-06-27", secondaryField: "Test_Company"
        )

        let factory = MockDocumentDetectorFactory()
        factory.mockVLMResponse = "YES"
        factory.mockDate = DateUtils.parseDate("2025-06-27")
        factory.mockSecondaryField = "Test_Company"

        let config = Configuration()
        let engine = BenchmarkEngine(
            configuration: config, documentType: .invoice, detectorFactory: factory
        )

        let pair = ModelPair(vlmModelName: config.modelName, textModelName: config.textModelName)
        // Only pdf1 has ground truth; pdf2 should be skipped
        let result = try await engine.benchmarkModelPair(
            pair,
            pdfPaths: [pdf1.path, pdf2.path],
            groundTruths: [pdf1.path: groundTruth],
            timeoutSeconds: 30
        )

        XCTAssertFalse(result.isDisqualified)
        XCTAssertEqual(result.documentResults.count, 1)
        XCTAssertEqual(result.documentResults.first?.filename, "invoice.pdf")
    }

    // MARK: - Benchmark: Preload Failure Disqualifies Pair

    func testBenchmarkPreloadFailureDisqualifies() async throws {
        let pdfPath = positiveDir.appendingPathComponent("invoice.pdf")
        createTestPDF(at: pdfPath)

        let groundTruth = GroundTruth(isMatch: true, documentType: .invoice, date: "2025-01-01")

        let factory = MockDocumentDetectorFactory()
        factory.shouldThrowOnPreload = true

        let config = Configuration()
        let engine = BenchmarkEngine(
            configuration: config, documentType: .invoice, detectorFactory: factory
        )

        let pair = ModelPair(vlmModelName: config.modelName, textModelName: config.textModelName)
        let result = try await engine.benchmarkModelPair(
            pair,
            pdfPaths: [pdfPath.path],
            groundTruths: [pdfPath.path: groundTruth],
            timeoutSeconds: 30
        )

        XCTAssertTrue(result.isDisqualified)
        XCTAssertTrue(result.disqualificationReason?.contains("Failed to load models") ?? false)
    }

    // MARK: - Benchmark: Release Models Called

    func testBenchmarkReleasesModelsBeforeEachPair() async throws {
        let pdfPath = positiveDir.appendingPathComponent("invoice.pdf")
        createTestPDF(at: pdfPath)

        let groundTruth = GroundTruth(
            isMatch: true, documentType: .invoice,
            date: "2025-06-27", secondaryField: "Test_Company"
        )

        let factory = MockDocumentDetectorFactory()
        factory.mockVLMResponse = "YES"
        factory.mockDate = DateUtils.parseDate("2025-06-27")
        factory.mockSecondaryField = "Test_Company"

        let config = Configuration()
        let engine = BenchmarkEngine(
            configuration: config, documentType: .invoice, detectorFactory: factory
        )

        let pair = ModelPair(vlmModelName: config.modelName, textModelName: config.textModelName)
        _ = try await engine.benchmarkModelPair(
            pair,
            pdfPaths: [pdfPath.path],
            groundTruths: [pdfPath.path: groundTruth],
            timeoutSeconds: 30
        )

        XCTAssertEqual(factory.releaseModelsCalled, 1)
    }

    // MARK: - Benchmark: Detector Error Gives Zero Score

    func testBenchmarkDetectorErrorGivesZeroScore() async throws {
        let pdfPath = positiveDir.appendingPathComponent("invoice.pdf")
        createTestPDF(at: pdfPath)

        let groundTruth = GroundTruth(
            isMatch: true, documentType: .invoice,
            date: "2025-01-01", secondaryField: "Company"
        )

        let factory = MockDocumentDetectorFactory()
        factory.shouldThrowError = true

        let config = Configuration()
        let engine = BenchmarkEngine(
            configuration: config, documentType: .invoice, detectorFactory: factory
        )

        let pair = ModelPair(vlmModelName: config.modelName, textModelName: config.textModelName)
        let result = try await engine.benchmarkModelPair(
            pair,
            pdfPaths: [pdfPath.path],
            groundTruths: [pdfPath.path: groundTruth],
            timeoutSeconds: 30
        )

        XCTAssertFalse(result.isDisqualified)
        XCTAssertEqual(result.documentResults.count, 1)
        XCTAssertEqual(result.documentResults.first?.documentScore, 0)
    }

    // MARK: - Memory Check: 80% Headroom Factor

    func testAvailableMemoryAppliesHeadroomFactor() {
        let totalPhysicalMB = ProcessInfo.processInfo.physicalMemory / 1_000_000
        let available = BenchmarkEngine.availableMemoryMB()
        let expectedWithHeadroom = UInt64(Double(totalPhysicalMB) * 0.8)

        // Allow ±1 MB rounding tolerance
        XCTAssertTrue(
            abs(Int64(available) - Int64(expectedWithHeadroom)) <= 1,
            "Expected ~\(expectedWithHeadroom) MB but got \(available) MB"
        )
    }

    // MARK: - Cleanup: Nothing to Delete

    func testCleanupNothingToDelete() {
        let config = Configuration()
        let engine = BenchmarkEngine(configuration: config, documentType: .invoice)

        let pair = ModelPair(vlmModelName: "org/keep-vlm", textModelName: "org/keep-text")
        engine.cleanupBenchmarkedModels(
            benchmarkedPairs: [pair],
            keepVLM: "org/keep-vlm",
            keepText: "org/keep-text"
        )
    }

    // MARK: - Cleanup: Deletes Benchmarked Models

    func testCleanupDeletesBenchmarkedModels() throws {
        let fakeCache = tempDirectory.appendingPathComponent("hub")
        let modelDir = fakeCache.appendingPathComponent("models--org--delete-me")
        try FileManager.default.createDirectory(at: modelDir, withIntermediateDirectories: true)
        try "fake weights".write(
            to: modelDir.appendingPathComponent("weights.bin"),
            atomically: true, encoding: .utf8
        )

        setenv("HUGGINGFACE_HUB_CACHE", fakeCache.path, 1)
        defer { unsetenv("HUGGINGFACE_HUB_CACHE") }

        let config = Configuration()
        let engine = BenchmarkEngine(configuration: config, documentType: .invoice)

        let pair = ModelPair(vlmModelName: "org/delete-me", textModelName: "org/keep-text")
        engine.cleanupBenchmarkedModels(
            benchmarkedPairs: [pair],
            keepVLM: "org/keep-vlm",
            keepText: "org/keep-text"
        )

        XCTAssertFalse(FileManager.default.fileExists(atPath: modelDir.path))
    }

    // MARK: - Cleanup: Skips Non-Existent Model Directories

    func testCleanupSkipsNonExistentModels() {
        let fakeCache = tempDirectory.appendingPathComponent("hub")
        try? FileManager.default.createDirectory(at: fakeCache, withIntermediateDirectories: true)

        setenv("HUGGINGFACE_HUB_CACHE", fakeCache.path, 1)
        defer { unsetenv("HUGGINGFACE_HUB_CACHE") }

        let config = Configuration()
        let engine = BenchmarkEngine(configuration: config, documentType: .invoice)

        let pair = ModelPair(vlmModelName: "org/nonexistent", textModelName: "org/keep-text")
        engine.cleanupBenchmarkedModels(
            benchmarkedPairs: [pair],
            keepVLM: "org/keep-vlm",
            keepText: "org/keep-text"
        )
    }

    // MARK: - HuggingFace Cache Path Resolution

    func testHuggingFaceCachePathDefault() {
        unsetenv("HUGGINGFACE_HUB_CACHE")
        unsetenv("HF_HOME")

        let path = BenchmarkEngine.huggingFaceCachePath()
        let expected = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".cache/huggingface/hub").path
        XCTAssertEqual(path, expected)
    }

    func testHuggingFaceCachePathFromHubCacheEnv() {
        setenv("HUGGINGFACE_HUB_CACHE", "/custom/hub/cache", 1)
        defer { unsetenv("HUGGINGFACE_HUB_CACHE") }

        let path = BenchmarkEngine.huggingFaceCachePath()
        XCTAssertEqual(path, "/custom/hub/cache")
    }

    func testHuggingFaceCachePathFromHFHomeEnv() {
        unsetenv("HUGGINGFACE_HUB_CACHE")
        setenv("HF_HOME", "/custom/hf_home", 1)
        defer { unsetenv("HF_HOME") }

        let path = BenchmarkEngine.huggingFaceCachePath()
        XCTAssertEqual(path, "/custom/hf_home/hub")
    }

    func testHuggingFaceCachePathHubCacheTakesPrecedence() {
        setenv("HUGGINGFACE_HUB_CACHE", "/hub/cache/wins", 1)
        setenv("HF_HOME", "/hf/home/loses", 1)
        defer {
            unsetenv("HUGGINGFACE_HUB_CACHE")
            unsetenv("HF_HOME")
        }

        let path = BenchmarkEngine.huggingFaceCachePath()
        XCTAssertEqual(path, "/hub/cache/wins")
    }

    // MARK: - Directory Size

    func testDirectorySizeCalculation() throws {
        let dir = tempDirectory.appendingPathComponent("size_test")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let data = Data(repeating: 0x42, count: 1024)
        try data.write(to: dir.appendingPathComponent("file1.bin"))
        try data.write(to: dir.appendingPathComponent("file2.bin"))

        let size = BenchmarkEngine.directorySize(at: dir.path)
        XCTAssertEqual(size, 2048)
    }

    func testDirectorySizeEmptyDirectory() throws {
        let dir = tempDirectory.appendingPathComponent("empty_dir")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let size = BenchmarkEngine.directorySize(at: dir.path)
        XCTAssertEqual(size, 0)
    }

    func testDirectorySizeNonExistentPath() {
        let size = BenchmarkEngine.directorySize(at: "/nonexistent/path")
        XCTAssertEqual(size, 0)
    }

    // MARK: - Memory Disqualification

    func testCheckMemoryDisqualifiesHugeModel() async throws {
        let pdfPath = positiveDir.appendingPathComponent("invoice.pdf")
        createTestPDF(at: pdfPath)

        let groundTruth = GroundTruth(isMatch: true, documentType: .invoice, date: "2025-01-01")

        let factory = MockDocumentDetectorFactory()
        let config = Configuration()
        let engine = BenchmarkEngine(
            configuration: config, documentType: .invoice, verbose: true, detectorFactory: factory
        )

        // Model names with 999B parameters → ~1.2 TB estimated, far exceeding any available memory
        let pair = ModelPair(vlmModelName: "org/huge-999B-4bit", textModelName: "org/huge-999B-4bit")
        let result = try await engine.benchmarkModelPair(
            pair,
            pdfPaths: [pdfPath.path],
            groundTruths: [pdfPath.path: groundTruth],
            timeoutSeconds: 30
        )

        XCTAssertTrue(result.isDisqualified)
        XCTAssertTrue(result.disqualificationReason?.contains("Insufficient memory") ?? false)
        XCTAssertEqual(result.documentResults.count, 0)
        // No detectors created — disqualified before processing
        XCTAssertEqual(factory.detectorsCreated, 0)
    }

    // MARK: - Timeout Disqualification

    func testBenchmarkTimeoutDisqualifiesPair() async throws {
        let pdfPath = positiveDir.appendingPathComponent("invoice.pdf")
        createTestPDF(at: pdfPath)

        let groundTruth = GroundTruth(isMatch: true, documentType: .invoice, date: "2025-01-01")

        let factory = MockDocumentDetectorFactory()
        factory.mockVLMResponse = "YES"
        factory.mockVLMDelay = 2 // VLM sleeps 2 seconds

        let config = Configuration()
        let engine = BenchmarkEngine(
            configuration: config, documentType: .invoice, detectorFactory: factory
        )

        let pair = ModelPair(vlmModelName: config.modelName, textModelName: config.textModelName)
        let result = try await engine.benchmarkModelPair(
            pair,
            pdfPaths: [pdfPath.path],
            groundTruths: [pdfPath.path: groundTruth],
            timeoutSeconds: 0.1 // Very short timeout to trigger timeout path
        )

        XCTAssertTrue(result.isDisqualified)
        XCTAssertTrue(result.disqualificationReason?.contains("timeout") ?? false)
    }
}
