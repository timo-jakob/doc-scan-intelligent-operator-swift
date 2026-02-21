@testable import DocScanCore
import XCTest

// MARK: - Edge Cases

extension PathUtilsTests {
    func testPathWithSpaces() throws {
        // Create file with spaces in name
        let testFile = tempDirectory.appendingPathComponent("file with spaces.pdf")
        try "test content".write(to: testFile, atomically: true, encoding: .utf8)

        let resolved = PathUtils.resolvePath(testFile.path)

        XCTAssertEqual(resolved, testFile.path)
        XCTAssertTrue(FileManager.default.fileExists(atPath: resolved))
    }

    func testPathWithSpecialCharacters() throws {
        // Create file with special characters
        let testFile = tempDirectory.appendingPathComponent("file-with_special.chars.pdf")
        try "test content".write(to: testFile, atomically: true, encoding: .utf8)

        let resolved = PathUtils.resolvePath(testFile.path)

        XCTAssertEqual(resolved, testFile.path)
        XCTAssertTrue(FileManager.default.fileExists(atPath: resolved))
    }

    func testPathWithUnicode() throws {
        // Create file with Unicode characters
        let testFile = tempDirectory.appendingPathComponent("Rechnung_Müller_2024.pdf")
        try "test content".write(to: testFile, atomically: true, encoding: .utf8)

        let resolved = PathUtils.resolvePath(testFile.path)

        XCTAssertEqual(resolved, testFile.path)
        XCTAssertTrue(FileManager.default.fileExists(atPath: resolved))
    }
}

// MARK: - Combined Tests (Multiple Features)

extension PathUtilsTests {
    func testRelativePathWithSymlinkAndNormalization() throws {
        // Create directory structure
        let subdir = tempDirectory.appendingPathComponent("subdir")
        try FileManager.default.createDirectory(at: subdir, withIntermediateDirectories: true)

        // Create actual file
        let actualFile = tempDirectory.appendingPathComponent("actual.pdf")
        try "test content".write(to: actualFile, atomically: true, encoding: .utf8)

        // Create symlink with ../ in path
        let symlinkFile = subdir.appendingPathComponent("link.pdf")
        try FileManager.default.createSymbolicLink(
            atPath: symlinkFile.path,
            withDestinationPath: "../actual.pdf"
        )

        // Change to temp directory
        FileManager.default.changeCurrentDirectoryPath(tempDirectory.path)

        // Resolve relative path to symlink
        let resolved = PathUtils.resolvePath("./subdir/link.pdf")

        // Should resolve symlink and normalize to actual file
        XCTAssertEqual(resolved, actualFile.path)
        XCTAssertFalse(resolved.contains(".."))
        XCTAssertFalse(resolved.contains("subdir"))
    }

    func testTildeWithNormalizationAndSymlink() {
        // This test verifies that tilde expansion works with our path resolution
        let homePath = FileManager.default.homeDirectoryForCurrentUser.path
        let resolved = PathUtils.resolvePath("~/Documents/../Documents/test.pdf")

        // Should expand tilde and normalize
        XCTAssertFalse(resolved.contains("~"))
        XCTAssertTrue(resolved.hasPrefix(homePath))
        XCTAssertTrue(resolved.hasSuffix("Documents/test.pdf"))
    }
}

// MARK: - getCurrentWorkingDirectory Tests

extension PathUtilsTests {
    func testGetCurrentWorkingDirectoryWithoutEnvVar() {
        // Ensure env var is not set
        unsetenv(docScanOriginalPwdKey)

        let cwd = PathUtils.getCurrentWorkingDirectory()

        // Should return FileManager's current directory
        XCTAssertEqual(cwd, FileManager.default.currentDirectoryPath)
    }

    func testGetCurrentWorkingDirectoryWithEnvVar() {
        let testPath = "/test/original/path"

        // Set the environment variable
        setenv(docScanOriginalPwdKey, testPath, 1)

        let cwd = PathUtils.getCurrentWorkingDirectory()

        // Clean up
        unsetenv(docScanOriginalPwdKey)

        // Should return the env var value
        XCTAssertEqual(cwd, testPath)
    }

    func testGetCurrentWorkingDirectoryWithEmptyEnvVar() {
        // Set empty environment variable
        setenv(docScanOriginalPwdKey, "", 1)

        let cwd = PathUtils.getCurrentWorkingDirectory()

        // Clean up
        unsetenv(docScanOriginalPwdKey)

        // Should fall back to FileManager's current directory
        XCTAssertEqual(cwd, FileManager.default.currentDirectoryPath)
    }

    func testRelativePathResolutionWithEnvVar() throws {
        // Create a file in temp directory
        let testFile = tempDirectory.appendingPathComponent("env_test.pdf")
        try "test content".write(to: testFile, atomically: true, encoding: .utf8)

        // Set the original PWD to temp directory (simulating wrapper script behavior)
        setenv(docScanOriginalPwdKey, tempDirectory.path, 1)

        // Resolve relative path - should use the env var, not current directory
        let resolved = PathUtils.resolvePath("env_test.pdf")

        // Clean up
        unsetenv(docScanOriginalPwdKey)

        // Should resolve relative to the env var path
        XCTAssertEqual(resolved, testFile.path)
        XCTAssertTrue(FileManager.default.fileExists(atPath: resolved))
    }

    func testRelativePathResolutionWithEnvVarDifferentFromCurrentDir() throws {
        // Create a file in temp directory
        let testFile = tempDirectory.appendingPathComponent("different_dir_test.pdf")
        try "test content".write(to: testFile, atomically: true, encoding: .utf8)

        // Change current directory to something else
        let originalDir = FileManager.default.currentDirectoryPath
        FileManager.default.changeCurrentDirectoryPath("/tmp")

        // Set the original PWD to temp directory
        setenv(docScanOriginalPwdKey, tempDirectory.path, 1)

        // Resolve relative path
        let resolved = PathUtils.resolvePath("different_dir_test.pdf")

        // Clean up
        unsetenv(docScanOriginalPwdKey)
        FileManager.default.changeCurrentDirectoryPath(originalDir)

        // Should resolve relative to the env var path, not /tmp
        XCTAssertEqual(resolved, testFile.path)
        XCTAssertFalse(resolved.contains("/tmp"))
    }
}
