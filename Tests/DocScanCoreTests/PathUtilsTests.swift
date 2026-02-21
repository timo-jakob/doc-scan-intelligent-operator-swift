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
}

// MARK: - Absolute Path Tests

extension PathUtilsTests {
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
}

// MARK: - Tilde Expansion Tests

extension PathUtilsTests {
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
}

// MARK: - Relative Path Tests

extension PathUtilsTests {
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
}

// MARK: - Path Normalization Tests (../ and ./)

extension PathUtilsTests {
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
}

// MARK: - Symlink Resolution Tests

extension PathUtilsTests {
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
}

// MARK: - Non-Existent File Tests

extension PathUtilsTests {
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
}
