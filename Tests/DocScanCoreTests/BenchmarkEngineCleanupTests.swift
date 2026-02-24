@testable import DocScanCore
import XCTest

final class BenchmarkEngineCleanupTests: XCTestCase {
    var engine: BenchmarkEngine!
    var tempDir: URL!

    override func setUp() {
        super.setUp()
        engine = BenchmarkEngine(
            configuration: Configuration(),
            documentType: .invoice
        )
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("BenchmarkCleanupTests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    // MARK: - cleanupBenchmarkedModels

    func testCleanupWithEmptyModelListDoesNotCrash() {
        // Should print "No benchmark models to clean up." and return safely
        engine.cleanupBenchmarkedModels(modelNames: [], keepModel: nil)
    }

    func testCleanupKeepsSelectedModel() throws {
        // Set HUGGINGFACE_HUB_CACHE to our temp dir so cleanup looks there
        let hubDir = tempDir.appendingPathComponent("hub")
        try FileManager.default.createDirectory(at: hubDir, withIntermediateDirectories: true)
        setenv("HUGGINGFACE_HUB_CACHE", hubDir.path, 1)
        defer { unsetenv("HUGGINGFACE_HUB_CACHE") }

        // Create model cache dirs matching the HF naming convention
        let keepDir = hubDir.appendingPathComponent("models--org--keep-model")
        let deleteDir = hubDir.appendingPathComponent("models--org--delete-model")
        try FileManager.default.createDirectory(at: keepDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: deleteDir, withIntermediateDirectories: true)

        // Write a file in each so they're non-empty
        try "data".write(to: keepDir.appendingPathComponent("model.bin"), atomically: true, encoding: .utf8)
        try "data".write(to: deleteDir.appendingPathComponent("model.bin"), atomically: true, encoding: .utf8)

        engine.cleanupBenchmarkedModels(
            modelNames: ["org/keep-model", "org/delete-model"],
            keepModel: "org/keep-model"
        )

        // The kept model dir should still exist
        XCTAssertTrue(FileManager.default.fileExists(atPath: keepDir.path))
        // The deleted model dir should be gone
        XCTAssertFalse(FileManager.default.fileExists(atPath: deleteDir.path))
    }

    // MARK: - directorySize

    func testDirectorySizeCalculatesCorrectly() throws {
        let subDir = tempDir.appendingPathComponent("sizetest")
        try FileManager.default.createDirectory(at: subDir, withIntermediateDirectories: true)

        // Write files with known content
        let data1 = Data(repeating: 0xAA, count: 1024) // 1 KB
        let data2 = Data(repeating: 0xBB, count: 2048) // 2 KB
        try data1.write(to: subDir.appendingPathComponent("file1.bin"))
        try data2.write(to: subDir.appendingPathComponent("file2.bin"))

        let size = BenchmarkEngine.directorySize(at: subDir.path)
        XCTAssertEqual(size, 3072, "Expected 3072 bytes (1024 + 2048)")
    }

    func testDirectorySizeReturnsZeroForNonExistentPath() {
        let size = BenchmarkEngine.directorySize(at: "/nonexistent/path/\(UUID().uuidString)")
        XCTAssertEqual(size, 0)
    }

    // MARK: - huggingFaceCachePath

    func testHuggingFaceCachePathRespectsEnvOverride() {
        let customPath = "/tmp/custom-hf-cache-\(UUID().uuidString)"
        setenv("HUGGINGFACE_HUB_CACHE", customPath, 1)
        defer { unsetenv("HUGGINGFACE_HUB_CACHE") }

        let resolved = BenchmarkEngine.huggingFaceCachePath()
        XCTAssertEqual(resolved, customPath)
    }

    func testHuggingFaceCachePathRespectsHFHome() {
        // Clear HUGGINGFACE_HUB_CACHE to test HF_HOME fallback
        unsetenv("HUGGINGFACE_HUB_CACHE")
        let hfHome = "/tmp/hf-home-\(UUID().uuidString)"
        setenv("HF_HOME", hfHome, 1)
        defer { unsetenv("HF_HOME") }

        let resolved = BenchmarkEngine.huggingFaceCachePath()
        XCTAssertEqual(resolved, (hfHome as NSString).appendingPathComponent("hub"))
    }
}
