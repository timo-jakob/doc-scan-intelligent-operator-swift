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

    // MARK: - renameToDirectory Tests

    func testRenameToDirectory() throws {
        // Create source file
        let sourceFile = tempDirectory.appendingPathComponent("source.txt")
        try "test content".write(to: sourceFile, atomically: true, encoding: .utf8)

        // Create target directory
        let targetDir = tempDirectory.appendingPathComponent("target_dir")
        try FileManager.default.createDirectory(at: targetDir, withIntermediateDirectories: true)

        // Move file to new directory
        let newPath = try renamer.renameToDirectory(
            from: sourceFile.path,
            to: targetDir.path,
            filename: "moved.txt",
            dryRun: false
        )

        let expectedPath = targetDir.appendingPathComponent("moved.txt").path
        XCTAssertEqual(newPath, expectedPath)
        XCTAssertTrue(FileManager.default.fileExists(atPath: newPath))
        XCTAssertFalse(FileManager.default.fileExists(atPath: sourceFile.path))
    }

    func testRenameToDirectoryDryRun() throws {
        // Create source file
        let sourceFile = tempDirectory.appendingPathComponent("source.txt")
        try "test content".write(to: sourceFile, atomically: true, encoding: .utf8)

        let targetDir = tempDirectory.appendingPathComponent("target_dir")

        // Dry run - should not actually move
        let newPath = try renamer.renameToDirectory(
            from: sourceFile.path,
            to: targetDir.path,
            filename: "moved.txt",
            dryRun: true
        )

        let expectedPath = targetDir.appendingPathComponent("moved.txt").path
        XCTAssertEqual(newPath, expectedPath)
        // Original file should still exist
        XCTAssertTrue(FileManager.default.fileExists(atPath: sourceFile.path))
        // Target should not exist
        XCTAssertFalse(FileManager.default.fileExists(atPath: newPath))
    }

    func testRenameToDirectoryCreatesDirectory() throws {
        // Create source file
        let sourceFile = tempDirectory.appendingPathComponent("source.txt")
        try "test content".write(to: sourceFile, atomically: true, encoding: .utf8)

        // Target directory doesn't exist yet
        let targetDir = tempDirectory.appendingPathComponent("new_directory")
        XCTAssertFalse(FileManager.default.fileExists(atPath: targetDir.path))

        // Move file - should create directory
        let newPath = try renamer.renameToDirectory(
            from: sourceFile.path,
            to: targetDir.path,
            filename: "moved.txt",
            dryRun: false
        )

        XCTAssertTrue(FileManager.default.fileExists(atPath: targetDir.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: newPath))
    }

    func testRenameToDirectoryWithCollision() throws {
        // Create source file
        let sourceFile = tempDirectory.appendingPathComponent("source.txt")
        try "source content".write(to: sourceFile, atomically: true, encoding: .utf8)

        // Create target directory with existing file
        let targetDir = tempDirectory.appendingPathComponent("target_dir")
        try FileManager.default.createDirectory(at: targetDir, withIntermediateDirectories: true)
        let existingFile = targetDir.appendingPathComponent("target.txt")
        try "existing content".write(to: existingFile, atomically: true, encoding: .utf8)

        // Move file with collision
        let newPath = try renamer.renameToDirectory(
            from: sourceFile.path,
            to: targetDir.path,
            filename: "target.txt",
            dryRun: false
        )

        let expectedPath = targetDir.appendingPathComponent("target_1.txt").path
        XCTAssertEqual(newPath, expectedPath)
        XCTAssertTrue(FileManager.default.fileExists(atPath: newPath))
        XCTAssertTrue(FileManager.default.fileExists(atPath: existingFile.path))
    }

    func testRenameToDirectorySourceNotFound() {
        let nonExistentFile = tempDirectory.appendingPathComponent("nonexistent.txt").path
        let targetDir = tempDirectory.path

        XCTAssertThrowsError(
            try renamer.renameToDirectory(
                from: nonExistentFile,
                to: targetDir,
                filename: "new.txt",
                dryRun: false
            )
        ) { error in
            guard let docScanError = error as? DocScanError else {
                XCTFail("Expected DocScanError")
                return
            }
            if case .fileNotFound = docScanError {
                // Expected
            } else {
                XCTFail("Expected fileNotFound error")
            }
        }
    }

    // MARK: - Multiple Collision Tests

    func testMultipleCollisions() throws {
        // Create source file
        let sourceFile = tempDirectory.appendingPathComponent("source.txt")
        try "source content".write(to: sourceFile, atomically: true, encoding: .utf8)

        // Create multiple colliding files
        let targetFile = tempDirectory.appendingPathComponent("target.txt")
        let targetFile1 = tempDirectory.appendingPathComponent("target_1.txt")
        let targetFile2 = tempDirectory.appendingPathComponent("target_2.txt")

        try "target content".write(to: targetFile, atomically: true, encoding: .utf8)
        try "target_1 content".write(to: targetFile1, atomically: true, encoding: .utf8)
        try "target_2 content".write(to: targetFile2, atomically: true, encoding: .utf8)

        // Rename with multiple collisions
        let newPath = try renamer.rename(
            from: sourceFile.path,
            to: "target.txt",
            dryRun: false
        )

        let expectedPath = tempDirectory.appendingPathComponent("target_3.txt").path
        XCTAssertEqual(newPath, expectedPath)
        XCTAssertTrue(FileManager.default.fileExists(atPath: newPath))
    }

    // MARK: - Verbose Mode Tests

    func testVerboseRenamer() throws {
        let verboseRenamer = FileRenamer(verbose: true)

        // Create test file
        let sourceFile = tempDirectory.appendingPathComponent("source.txt")
        try "test content".write(to: sourceFile, atomically: true, encoding: .utf8)

        // Should not crash and still work correctly
        let newPath = try verboseRenamer.rename(
            from: sourceFile.path,
            to: "renamed.txt",
            dryRun: false
        )

        XCTAssertTrue(FileManager.default.fileExists(atPath: newPath))
    }

    func testVerboseDryRun() throws {
        let verboseRenamer = FileRenamer(verbose: true)

        // Create test file
        let sourceFile = tempDirectory.appendingPathComponent("source.txt")
        try "test content".write(to: sourceFile, atomically: true, encoding: .utf8)

        // Dry run with verbose mode
        _ = try verboseRenamer.rename(
            from: sourceFile.path,
            to: "renamed.txt",
            dryRun: true
        )

        // Original file should still exist
        XCTAssertTrue(FileManager.default.fileExists(atPath: sourceFile.path))
    }

    func testVerboseCollision() throws {
        let verboseRenamer = FileRenamer(verbose: true)

        // Create source and target files
        let sourceFile = tempDirectory.appendingPathComponent("source.txt")
        let targetFile = tempDirectory.appendingPathComponent("target.txt")

        try "source content".write(to: sourceFile, atomically: true, encoding: .utf8)
        try "target content".write(to: targetFile, atomically: true, encoding: .utf8)

        // Rename with collision in verbose mode
        let newPath = try verboseRenamer.rename(
            from: sourceFile.path,
            to: "target.txt",
            dryRun: false
        )

        let expectedPath = tempDirectory.appendingPathComponent("target_1.txt").path
        XCTAssertEqual(newPath, expectedPath)
    }

    // MARK: - File Without Extension Tests

    func testRenameFileWithoutExtension() throws {
        // Create test file without extension
        let sourceFile = tempDirectory.appendingPathComponent("source")
        try "test content".write(to: sourceFile, atomically: true, encoding: .utf8)

        let newPath = try renamer.rename(
            from: sourceFile.path,
            to: "renamed",
            dryRun: false
        )

        let expectedPath = tempDirectory.appendingPathComponent("renamed").path
        XCTAssertEqual(newPath, expectedPath)
        XCTAssertTrue(FileManager.default.fileExists(atPath: newPath))
    }

    func testCollisionFileWithoutExtension() throws {
        // Create source and target files without extension
        let sourceFile = tempDirectory.appendingPathComponent("source")
        let targetFile = tempDirectory.appendingPathComponent("target")

        try "source content".write(to: sourceFile, atomically: true, encoding: .utf8)
        try "target content".write(to: targetFile, atomically: true, encoding: .utf8)

        let newPath = try renamer.rename(
            from: sourceFile.path,
            to: "target",
            dryRun: false
        )

        let expectedPath = tempDirectory.appendingPathComponent("target_1").path
        XCTAssertEqual(newPath, expectedPath)
    }

    // MARK: - Verbose renameToDirectory Tests

    func testVerboseRenameToDirectory() throws {
        let verboseRenamer = FileRenamer(verbose: true)

        // Create source file
        let sourceFile = tempDirectory.appendingPathComponent("source.txt")
        try "test content".write(to: sourceFile, atomically: true, encoding: .utf8)

        let targetDir = tempDirectory.appendingPathComponent("target_dir")

        // Move file with verbose mode
        let newPath = try verboseRenamer.renameToDirectory(
            from: sourceFile.path,
            to: targetDir.path,
            filename: "moved.txt",
            dryRun: false
        )

        XCTAssertTrue(FileManager.default.fileExists(atPath: newPath))
    }

    func testVerboseRenameToDirectoryDryRun() throws {
        let verboseRenamer = FileRenamer(verbose: true)

        // Create source file
        let sourceFile = tempDirectory.appendingPathComponent("source.txt")
        try "test content".write(to: sourceFile, atomically: true, encoding: .utf8)

        let targetDir = tempDirectory.appendingPathComponent("target_dir")

        // Dry run with verbose mode
        _ = try verboseRenamer.renameToDirectory(
            from: sourceFile.path,
            to: targetDir.path,
            filename: "moved.txt",
            dryRun: true
        )

        // Original file should still exist
        XCTAssertTrue(FileManager.default.fileExists(atPath: sourceFile.path))
    }
}
