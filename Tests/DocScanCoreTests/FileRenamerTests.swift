import XCTest
@testable import DocScanCore

final class FileRenamerTests: XCTestCase {
    var tempDirectory: URL!
    var renamer: FileRenamer!

    override func setUp() {
        super.setUp()
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(
            at: tempDirectory,
            withIntermediateDirectories: true
        )
        renamer = FileRenamer(verbose: false)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDirectory)
        super.tearDown()
    }

    func testRenameFile() throws {
        // Create test file
        let sourceFile = tempDirectory.appendingPathComponent("source.txt")
        try "test content".write(to: sourceFile, atomically: true, encoding: .utf8)

        // Rename
        let newPath = try renamer.rename(
            from: sourceFile.path,
            to: "renamed.txt",
            dryRun: false
        )

        let expectedPath = tempDirectory.appendingPathComponent("renamed.txt").path
        XCTAssertEqual(newPath, expectedPath)
        XCTAssertTrue(FileManager.default.fileExists(atPath: newPath))
        XCTAssertFalse(FileManager.default.fileExists(atPath: sourceFile.path))
    }

    func testDryRun() throws {
        // Create test file
        let sourceFile = tempDirectory.appendingPathComponent("source.txt")
        try "test content".write(to: sourceFile, atomically: true, encoding: .utf8)

        // Dry run
        let newPath = try renamer.rename(
            from: sourceFile.path,
            to: "renamed.txt",
            dryRun: true
        )

        let expectedPath = tempDirectory.appendingPathComponent("renamed.txt").path
        XCTAssertEqual(newPath, expectedPath)
        // Original file should still exist
        XCTAssertTrue(FileManager.default.fileExists(atPath: sourceFile.path))
        // New file should not exist
        XCTAssertFalse(FileManager.default.fileExists(atPath: newPath))
    }

    func testCollisionHandling() throws {
        // Create source and target files
        let sourceFile = tempDirectory.appendingPathComponent("source.txt")
        let targetFile = tempDirectory.appendingPathComponent("target.txt")

        try "source content".write(to: sourceFile, atomically: true, encoding: .utf8)
        try "target content".write(to: targetFile, atomically: true, encoding: .utf8)

        // Rename with collision
        let newPath = try renamer.rename(
            from: sourceFile.path,
            to: "target.txt",
            dryRun: false
        )

        let expectedPath = tempDirectory.appendingPathComponent("target_1.txt").path
        XCTAssertEqual(newPath, expectedPath)
        XCTAssertTrue(FileManager.default.fileExists(atPath: newPath))
        // Original target should still exist
        XCTAssertTrue(FileManager.default.fileExists(atPath: targetFile.path))
    }

    func testSameNameNoRename() throws {
        // Create test file
        let sourceFile = tempDirectory.appendingPathComponent("same.txt")
        try "test content".write(to: sourceFile, atomically: true, encoding: .utf8)

        // Try to rename to same name
        let newPath = try renamer.rename(
            from: sourceFile.path,
            to: "same.txt",
            dryRun: false
        )

        XCTAssertEqual(newPath, sourceFile.path)
        XCTAssertTrue(FileManager.default.fileExists(atPath: sourceFile.path))
    }

    func testNonExistentFile() {
        let nonExistentFile = tempDirectory.appendingPathComponent("nonexistent.txt").path

        XCTAssertThrowsError(
            try renamer.rename(from: nonExistentFile, to: "new.txt", dryRun: false)
        ) { error in
            XCTAssertTrue(error is DocScanError)
        }
    }
}
