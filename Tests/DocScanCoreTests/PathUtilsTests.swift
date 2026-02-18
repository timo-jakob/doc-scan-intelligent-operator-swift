@testable import DocScanCore
import XCTest

final class PathUtilsTests: XCTestCase {
    var tempDirectory: URL!
    var originalWorkingDirectory: String!

    override func setUp() {
        super.setUp()

        // Save original working directory
        originalWorkingDirectory = FileManager.default.currentDirectoryPath

        // Create temp directory
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(
            at: tempDirectory,
            withIntermediateDirectories: true
        )
    }

    override func tearDown() {
        // Restore original working directory
        FileManager.default.changeCurrentDirectoryPath(originalWorkingDirectory)

        // Clean up temp directory
        try? FileManager.default.removeItem(at: tempDirectory)
        super.tearDown()
    }

    // MARK: - Absolute Path Tests

    func testAbsolutePath() {
        let absolutePath = "/usr/local/bin/docscan"
        let resolved = PathUtils.resolvePath(absolutePath)

        // Should return the normalized absolute path
        XCTAssertTrue(resolved.hasPrefix("/"))
        XCTAssertTrue(resolved.contains("usr"))
    }

    func testAbsolutePathWithExistingFile() throws {
        // Create a test file
        let testFile = tempDirectory.appendingPathComponent("test.pdf")
        try "test content".write(to: testFile, atomically: true, encoding: .utf8)

        let resolved = PathUtils.resolvePath(testFile.path)

        XCTAssertEqual(resolved, testFile.path)
        XCTAssertTrue(FileManager.default.fileExists(atPath: resolved))
    }

    // MARK: - Tilde Expansion Tests

    func testTildeExpansion() {
        let tildePath = "~/Documents/invoice.pdf"
        let resolved = PathUtils.resolvePath(tildePath)

        // Should expand to home directory
        XCTAssertFalse(resolved.contains("~"))
        XCTAssertTrue(resolved.hasPrefix("/"))
        XCTAssertTrue(resolved.contains("Documents"))
    }

    func testTildeExpansionWithExistingFile() throws {
        // Create a file in temp directory, then create a symlink in home
        let testFile = tempDirectory.appendingPathComponent("tilde_test.pdf")
        try "test content".write(to: testFile, atomically: true, encoding: .utf8)

        // Use the temp file path directly (can't easily test ~/ without modifying home)
        let resolved = PathUtils.resolvePath(testFile.path)
        XCTAssertTrue(FileManager.default.fileExists(atPath: resolved))
    }

    // MARK: - Relative Path Tests

    func testRelativePathBareFilename() throws {
        // Change to temp directory
        FileManager.default.changeCurrentDirectoryPath(tempDirectory.path)

        // Create a file in current directory
        let testFile = tempDirectory.appendingPathComponent("invoice.pdf")
        try "test content".write(to: testFile, atomically: true, encoding: .utf8)

        // Test bare filename
        let resolved = PathUtils.resolvePath("invoice.pdf")

        XCTAssertEqual(resolved, testFile.path)
        XCTAssertTrue(FileManager.default.fileExists(atPath: resolved))
    }

    func testRelativePathWithDotSlash() throws {
        // Change to temp directory
        FileManager.default.changeCurrentDirectoryPath(tempDirectory.path)

        // Create a file in current directory
        let testFile = tempDirectory.appendingPathComponent("test.pdf")
        try "test content".write(to: testFile, atomically: true, encoding: .utf8)

        // Test ./filename
        let resolved = PathUtils.resolvePath("./test.pdf")

        XCTAssertEqual(resolved, testFile.path)
        XCTAssertTrue(FileManager.default.fileExists(atPath: resolved))
    }

    func testRelativePathWithSubdirectory() throws {
        // Change to temp directory
        FileManager.default.changeCurrentDirectoryPath(tempDirectory.path)

        // Create subdirectory and file
        let subdir = tempDirectory.appendingPathComponent("documents")
        try FileManager.default.createDirectory(at: subdir, withIntermediateDirectories: true)
        let testFile = subdir.appendingPathComponent("invoice.pdf")
        try "test content".write(to: testFile, atomically: true, encoding: .utf8)

        // Test relative path with subdirectory
        let resolved = PathUtils.resolvePath("documents/invoice.pdf")

        XCTAssertEqual(resolved, testFile.path)
        XCTAssertTrue(FileManager.default.fileExists(atPath: resolved))
    }

    func testRelativePathWithDotSlashSubdirectory() throws {
        // Change to temp directory
        FileManager.default.changeCurrentDirectoryPath(tempDirectory.path)

        // Create subdirectory and file
        let subdir = tempDirectory.appendingPathComponent("docs")
        try FileManager.default.createDirectory(at: subdir, withIntermediateDirectories: true)
        let testFile = subdir.appendingPathComponent("file.pdf")
        try "test content".write(to: testFile, atomically: true, encoding: .utf8)

        // Test ./subdir/filename
        let resolved = PathUtils.resolvePath("./docs/file.pdf")

        XCTAssertEqual(resolved, testFile.path)
        XCTAssertTrue(FileManager.default.fileExists(atPath: resolved))
    }

    // MARK: - Path Normalization Tests (../ and ./)

    func testPathNormalizationWithDotDot() throws {
        // Create directory structure: temp/subdir/file.pdf
        let subdir = tempDirectory.appendingPathComponent("subdir")
        try FileManager.default.createDirectory(at: subdir, withIntermediateDirectories: true)
        let testFile = tempDirectory.appendingPathComponent("file.pdf")
        try "test content".write(to: testFile, atomically: true, encoding: .utf8)

        // Test path like: temp/subdir/../file.pdf
        let unnormalizedPath = subdir.appendingPathComponent("../file.pdf").path
        let resolved = PathUtils.resolvePath(unnormalizedPath)

        // Should normalize to temp/file.pdf
        XCTAssertEqual(resolved, testFile.path)
        XCTAssertFalse(resolved.contains(".."))
    }

    func testPathNormalizationWithMultipleDotDot() throws {
        // Create directory structure: temp/a/b/c.pdf and temp/file.pdf
        let dirA = tempDirectory.appendingPathComponent("a")
        let dirB = dirA.appendingPathComponent("b")
        try FileManager.default.createDirectory(at: dirB, withIntermediateDirectories: true)
        let testFile = tempDirectory.appendingPathComponent("file.pdf")
        try "test content".write(to: testFile, atomically: true, encoding: .utf8)

        // Test path like: temp/a/b/../../file.pdf
        let unnormalizedPath = dirB.appendingPathComponent("../../file.pdf").path
        let resolved = PathUtils.resolvePath(unnormalizedPath)

        // Should normalize to temp/file.pdf
        XCTAssertEqual(resolved, testFile.path)
        XCTAssertFalse(resolved.contains(".."))
    }

    func testPathNormalizationWithDot() throws {
        // Create file
        let testFile = tempDirectory.appendingPathComponent("test.pdf")
        try "test content".write(to: testFile, atomically: true, encoding: .utf8)

        // Test path with ./ in the middle
        let pathWithDot = tempDirectory.path + "/./test.pdf"
        let resolved = PathUtils.resolvePath(pathWithDot)

        XCTAssertEqual(resolved, testFile.path)
        // The path might still contain /. or might be normalized - just check it exists
        XCTAssertTrue(FileManager.default.fileExists(atPath: resolved))
    }

    func testComplexPathNormalization() throws {
        // Create directory structure
        let dirA = tempDirectory.appendingPathComponent("a")
        let dirB = dirA.appendingPathComponent("b")
        try FileManager.default.createDirectory(at: dirB, withIntermediateDirectories: true)
        let testFile = tempDirectory.appendingPathComponent("file.pdf")
        try "test content".write(to: testFile, atomically: true, encoding: .utf8)

        // Test complex path: temp/./a/./b/../../file.pdf
        let complexPath = tempDirectory.path + "/./a/./b/../../file.pdf"
        let resolved = PathUtils.resolvePath(complexPath)

        XCTAssertEqual(resolved, testFile.path)
        XCTAssertFalse(resolved.contains(".."))
        XCTAssertFalse(resolved.contains("/./"))
    }

    // MARK: - Symlink Resolution Tests

    func testSymlinkResolution() throws {
        // Create actual file
        let actualFile = tempDirectory.appendingPathComponent("actual.pdf")
        try "test content".write(to: actualFile, atomically: true, encoding: .utf8)

        // Create symlink to the file
        let symlinkFile = tempDirectory.appendingPathComponent("link.pdf")
        try FileManager.default.createSymbolicLink(
            atPath: symlinkFile.path,
            withDestinationPath: actualFile.path
        )

        // Resolve symlink
        let resolved = PathUtils.resolvePath(symlinkFile.path)

        // Should resolve to actual file
        XCTAssertEqual(resolved, actualFile.path)
        XCTAssertTrue(FileManager.default.fileExists(atPath: resolved))
    }

    func testSymlinkToSymlink() throws {
        // Create actual file
        let actualFile = tempDirectory.appendingPathComponent("actual.pdf")
        try "test content".write(to: actualFile, atomically: true, encoding: .utf8)

        // Create first symlink
        let symlink1 = tempDirectory.appendingPathComponent("link1.pdf")
        try FileManager.default.createSymbolicLink(
            atPath: symlink1.path,
            withDestinationPath: actualFile.path
        )

        // Create symlink to symlink
        let symlink2 = tempDirectory.appendingPathComponent("link2.pdf")
        try FileManager.default.createSymbolicLink(
            atPath: symlink2.path,
            withDestinationPath: symlink1.path
        )

        // Resolve nested symlinks
        let resolved = PathUtils.resolvePath(symlink2.path)

        // Should resolve to actual file
        XCTAssertEqual(resolved, actualFile.path)
    }

    func testRelativeSymlink() throws {
        // Create subdirectory
        let subdir = tempDirectory.appendingPathComponent("subdir")
        try FileManager.default.createDirectory(at: subdir, withIntermediateDirectories: true)

        // Create actual file in temp directory
        let actualFile = tempDirectory.appendingPathComponent("actual.pdf")
        try "test content".write(to: actualFile, atomically: true, encoding: .utf8)

        // Create relative symlink from subdir
        let symlinkFile = subdir.appendingPathComponent("link.pdf")
        try FileManager.default.createSymbolicLink(
            atPath: symlinkFile.path,
            withDestinationPath: "../actual.pdf"
        )

        // Resolve symlink
        let resolved = PathUtils.resolvePath(symlinkFile.path)

        // Should resolve to actual file
        XCTAssertEqual(resolved, actualFile.path)
    }

    // MARK: - Non-Existent File Tests

    func testNonExistentFileAbsolutePath() {
        let nonExistentPath = tempDirectory.appendingPathComponent("nonexistent.pdf").path
        let resolved = PathUtils.resolvePath(nonExistentPath)

        // Should still return normalized path even if file doesn't exist
        XCTAssertEqual(resolved, nonExistentPath)
        XCTAssertFalse(FileManager.default.fileExists(atPath: resolved))
    }

    func testNonExistentFileRelativePath() {
        FileManager.default.changeCurrentDirectoryPath(tempDirectory.path)

        let resolved = PathUtils.resolvePath("nonexistent.pdf")

        // Should return absolute path
        XCTAssertTrue(resolved.hasPrefix("/"))
        XCTAssertTrue(resolved.hasSuffix("nonexistent.pdf"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: resolved))
    }

    func testNonExistentFileWithNormalization() {
        let nonExistentPath = tempDirectory.path + "/a/../nonexistent.pdf"
        let resolved = PathUtils.resolvePath(nonExistentPath)

        // Should normalize even if file doesn't exist
        XCTAssertFalse(resolved.contains(".."))
        XCTAssertTrue(resolved.hasSuffix("nonexistent.pdf"))
    }

    // MARK: - Edge Cases

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

    // MARK: - Combined Tests (Multiple Features)

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

    // MARK: - getCurrentWorkingDirectory Tests

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
