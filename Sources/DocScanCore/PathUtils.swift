import Foundation

/// Utilities for resolving and normalizing file paths
public enum PathUtils {
    /// Environment variable used to pass the original working directory from wrapper scripts
    public static let originalPWDEnvironmentKey = "DOCSCAN_ORIGINAL_PWD"

    /// Returns the effective current working directory
    /// Uses DOCSCAN_ORIGINAL_PWD environment variable if set (from wrapper script),
    /// otherwise falls back to FileManager.default.currentDirectoryPath
    public static func getCurrentWorkingDirectory() -> String {
        if let originalPwd = ProcessInfo.processInfo.environment[originalPWDEnvironmentKey],
           !originalPwd.isEmpty,
           originalPwd.hasPrefix("/") {
            return originalPwd
        }
        return FileManager.default.currentDirectoryPath
    }

    /// Resolves a path to an absolute, normalized path with symlinks resolved
    ///
    /// This function handles:
    /// - Tilde expansion (`~/Documents/file.pdf`)
    /// - Relative paths (`./file.pdf`, `../file.pdf`)
    /// - Absolute paths (`/Users/name/file.pdf`)
    /// - Path normalization (resolves `.` and `..` components)
    /// - Symlink resolution (if file exists)
    ///
    /// - Parameter path: The path to resolve (can be relative, absolute, or contain `~`)
    /// - Returns: The absolute, normalized path with symlinks resolved
    public static func resolvePath(_ path: String) -> String {
        // Convert to absolute path
        let absolutePath: String
        if path.hasPrefix("~") {
            // Home directory path - expand tilde
            absolutePath = (path as NSString).expandingTildeInPath
        } else if path.hasPrefix("/") {
            // Already absolute path
            absolutePath = path
        } else {
            // Relative path - convert to absolute using URL for proper path handling
            let currentDir = getCurrentWorkingDirectory()
            let currentDirURL = URL(fileURLWithPath: currentDir)
            absolutePath = currentDirURL.appendingPathComponent(path).path
        }

        // Normalize the path (handles ./ and ../ components) and resolve symlinks
        let normalizedURL = URL(fileURLWithPath: absolutePath).standardized
        return normalizedURL.resolvingSymlinksInPath().path
    }
}
