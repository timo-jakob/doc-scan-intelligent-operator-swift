import Foundation

/// Handles safe file renaming with collision detection
public struct FileRenamer: Sendable {
    private let verbose: Bool

    public init(verbose: Bool = false) {
        self.verbose = verbose
    }

    /// Rename a file, handling collisions
    public func rename(
        from sourcePath: String,
        to targetFilename: String,
        dryRun: Bool = false
    ) throws -> String {
        let sourceURL = URL(fileURLWithPath: sourcePath)
        let sourceDirectory = sourceURL.deletingLastPathComponent()
        let targetURL = sourceDirectory.appendingPathComponent(targetFilename)

        // Validate target stays within source directory (prevent path traversal)
        let resolvedTarget = targetURL.standardized
        guard resolvedTarget.path.hasPrefix(sourceDirectory.standardized.path) else {
            throw DocScanError.fileOperationFailed(
                "Target filename would escape source directory: \(targetFilename)"
            )
        }

        // Check if source exists
        guard FileManager.default.fileExists(atPath: sourcePath) else {
            throw DocScanError.fileNotFound(sourcePath)
        }

        // If source and target are the same, no rename needed
        if sourcePath == targetURL.path {
            if verbose {
                print("File already has target name: \(targetFilename)")
            }
            return sourcePath
        }

        if dryRun {
            let finalURL = try findAvailableName(for: targetURL)
            if verbose {
                print("DRY RUN: Would rename:")
                print("  From: \(sourcePath)")
                print("  To:   \(finalURL.path)")
            }
            return finalURL.path
        }

        // Perform atomic rename with retry-based collision handling
        let finalURL = try moveWithRetry(from: sourceURL, to: targetURL)
        if verbose {
            print("Renamed:")
            print("  From: \(sourcePath)")
            print("  To:   \(finalURL.path)")
        }
        return finalURL.path
    }

    /// Find an available filename by checking for collisions (used for dry-run)
    private func findAvailableName(for targetURL: URL) throws -> URL {
        if !FileManager.default.fileExists(atPath: targetURL.path) {
            return targetURL
        }

        let directory = targetURL.deletingLastPathComponent()
        let filename = targetURL.deletingPathExtension().lastPathComponent
        let ext = targetURL.pathExtension

        for counter in 1 ... 1000 {
            let newFilename = ext.isEmpty
                ? "\(filename)_\(counter)"
                : "\(filename)_\(counter).\(ext)"
            let candidateURL = directory.appendingPathComponent(newFilename)
            if !FileManager.default.fileExists(atPath: candidateURL.path) {
                return candidateURL
            }
        }
        throw DocScanError.fileOperationFailed("Too many file collisions")
    }

    /// Atomically rename a file, retrying with incremented counters on collision.
    /// Eliminates the TOCTOU race between existence check and rename.
    private func moveWithRetry(from sourceURL: URL, to targetURL: URL) throws -> URL {
        // Try the target directly first
        do {
            try FileManager.default.moveItem(at: sourceURL, to: targetURL)
            return targetURL
        } catch let error as CocoaError where error.code == .fileWriteFileExists {
            // Fall through to collision handling
        } catch {
            throw DocScanError.fileOperationFailed("Failed to rename file: \(error.localizedDescription)")
        }

        let directory = targetURL.deletingLastPathComponent()
        let filename = targetURL.deletingPathExtension().lastPathComponent
        let ext = targetURL.pathExtension

        for counter in 1 ... 1000 {
            let newFilename = ext.isEmpty
                ? "\(filename)_\(counter)"
                : "\(filename)_\(counter).\(ext)"
            let candidateURL = directory.appendingPathComponent(newFilename)
            do {
                try FileManager.default.moveItem(at: sourceURL, to: candidateURL)
                if verbose {
                    print("Collision detected, using: \(candidateURL.lastPathComponent)")
                }
                return candidateURL
            } catch let error as CocoaError where error.code == .fileWriteFileExists {
                continue
            } catch {
                throw DocScanError.fileOperationFailed("Failed to rename file: \(error.localizedDescription)")
            }
        }
        throw DocScanError.fileOperationFailed("Too many file collisions")
    }

    /// Rename file to a different directory
    public func renameToDirectory(
        from sourcePath: String,
        to targetDirectory: String,
        filename: String,
        dryRun: Bool = false
    ) throws -> String {
        let sourceURL = URL(fileURLWithPath: sourcePath)

        // Ensure target directory exists
        if !dryRun {
            try FileManager.default.createDirectory(
                atPath: targetDirectory,
                withIntermediateDirectories: true,
                attributes: nil
            )
        }

        let targetURL = URL(fileURLWithPath: targetDirectory)
            .appendingPathComponent(filename)

        // Check if source exists
        guard FileManager.default.fileExists(atPath: sourcePath) else {
            throw DocScanError.fileNotFound(sourcePath)
        }

        if dryRun {
            let finalURL = try findAvailableName(for: targetURL)
            if verbose {
                print("DRY RUN: Would move:")
                print("  From: \(sourcePath)")
                print("  To:   \(finalURL.path)")
            }
            return finalURL.path
        }

        // Perform atomic move with retry-based collision handling
        let finalURL = try moveWithRetry(from: sourceURL, to: targetURL)
        if verbose {
            print("Moved:")
            print("  From: \(sourcePath)")
            print("  To:   \(finalURL.path)")
        }
        return finalURL.path
    }
}
