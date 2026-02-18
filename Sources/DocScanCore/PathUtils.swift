import Foundation

/// Environment variable used to pass the original working directory from wrapper scripts
/// This is needed when the binary is launched via a wrapper that changes directory
/// (e.g., to find MLX Metal library bundles)
public let docScanOriginalPwdKey = "DOCSCAN_ORIGINAL_PWD"

/// Utilities for resolving and normalizing file paths
public enum PathUtils {
    /// Returns the effective current working directory
    /// Uses DOCSCAN_ORIGINAL_PWD environment variable if set (from wrapper script),
    /// otherwise falls back to FileManager.default.currentDirectoryPath
    public static func getCurrentWorkingDirectory() -> String {
        if let originalPwd = ProcessInfo.processInfo.environment[docScanOriginalPwdKey],
           !originalPwd.isEmpty {
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
        let resolvedPath: String
        do {
            // Resolve symlinks if the path exists
            resolvedPath = try normalizedURL.resolvingSymlinksInPath().path
        } catch {
            // If symlink resolution fails (e.g., file doesn't exist yet), use standardized path
            resolvedPath = normalizedURL.path
        }

        return resolvedPath
    }
}
