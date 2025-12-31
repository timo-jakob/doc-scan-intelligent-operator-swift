import Foundation

/// Utilities for resolving and normalizing file paths
public struct PathUtils {
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
            let currentDirURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
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
