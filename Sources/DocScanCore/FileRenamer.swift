import Foundation

/// Handles safe file renaming with collision detection
public class FileRenamer {
    private let fileManager = FileManager.default
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

        // Check if source exists
        guard fileManager.fileExists(atPath: sourcePath) else {
            throw DocScanError.fileNotFound(sourcePath)
        }

        // If source and target are the same, no rename needed
        if sourcePath == targetURL.path {
            if verbose {
                print("File already has target name: \(targetFilename)")
            }
            return sourcePath
        }

        // Handle collision
        let finalURL = try handleCollision(targetURL: targetURL)

        if dryRun {
            if verbose {
                print("DRY RUN: Would rename:")
                print("  From: \(sourcePath)")
                print("  To:   \(finalURL.path)")
            }
            return finalURL.path
        }

        // Perform rename
        do {
            try fileManager.moveItem(at: sourceURL, to: finalURL)
            if verbose {
                print("Renamed:")
                print("  From: \(sourcePath)")
                print("  To:   \(finalURL.path)")
            }
            return finalURL.path
        } catch {
            throw DocScanError.fileOperationFailed("Failed to rename file: \(error.localizedDescription)")
        }
    }

    /// Handle filename collision by adding a counter
    private func handleCollision(targetURL: URL) throws -> URL {
        var finalURL = targetURL
        var counter = 1

        // If target doesn't exist, use it as-is
        if !fileManager.fileExists(atPath: targetURL.path) {
            return targetURL
        }

        // Add counter until we find a non-existing filename
        let directory = targetURL.deletingLastPathComponent()
        let filename = targetURL.deletingPathExtension().lastPathComponent
        let ext = targetURL.pathExtension

        while fileManager.fileExists(atPath: finalURL.path) {
            let newFilename = if ext.isEmpty {
                "\(filename)_\(counter)"
            } else {
                "\(filename)_\(counter).\(ext)"
            }

            finalURL = directory.appendingPathComponent(newFilename)
            counter += 1

            // Safety check to prevent infinite loop
            if counter > 1000 {
                throw DocScanError.fileOperationFailed("Too many file collisions")
            }
        }

        if verbose {
            print("Collision detected, using: \(finalURL.lastPathComponent)")
        }

        return finalURL
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
            try fileManager.createDirectory(
                atPath: targetDirectory,
                withIntermediateDirectories: true,
                attributes: nil
            )
        }

        let targetURL = URL(fileURLWithPath: targetDirectory)
            .appendingPathComponent(filename)

        // Check if source exists
        guard fileManager.fileExists(atPath: sourcePath) else {
            throw DocScanError.fileNotFound(sourcePath)
        }

        // Handle collision
        let finalURL = try handleCollision(targetURL: targetURL)

        if dryRun {
            if verbose {
                print("DRY RUN: Would move:")
                print("  From: \(sourcePath)")
                print("  To:   \(finalURL.path)")
            }
            return finalURL.path
        }

        // Perform move
        do {
            try fileManager.moveItem(at: sourceURL, to: finalURL)
            if verbose {
                print("Moved:")
                print("  From: \(sourcePath)")
                print("  To:   \(finalURL.path)")
            }
            return finalURL.path
        } catch {
            throw DocScanError.fileOperationFailed("Failed to move file: \(error.localizedDescription)")
        }
    }
}
