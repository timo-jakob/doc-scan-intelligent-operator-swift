import Foundation

// MARK: - Model Cache Cleanup

public extension BenchmarkEngine {
    /// Remove cached models that were downloaded during benchmarking but are not the final selected pair.
    /// - Parameters:
    ///   - benchmarkedPairs: All model pairs that were benchmarked
    ///   - keepVLM: VLM model name to keep (final selected)
    ///   - keepText: TextLLM model name to keep (final selected)
    func cleanupBenchmarkedModels(
        benchmarkedPairs: [ModelPair],
        keepVLM: String,
        keepText: String
    ) {
        let keepModels: Set<String> = [keepVLM, keepText]

        // Collect all unique model names from benchmarked pairs
        var benchmarkedModels: Set<String> = []
        for pair in benchmarkedPairs {
            benchmarkedModels.insert(pair.vlmModelName)
            benchmarkedModels.insert(pair.textModelName)
        }

        // Only delete models that were benchmarked and are NOT in the keep set
        let toDelete = benchmarkedModels.subtracting(keepModels)

        guard !toDelete.isEmpty else {
            print("No benchmark models to clean up.")
            return
        }

        let fileManager = FileManager.default
        let hubCache = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent(".cache/huggingface/hub")
            .path

        for modelName in toDelete.sorted() {
            // mlx-community/Qwen2-VL-2B-Instruct-4bit → models--mlx-community--Qwen2-VL-2B-Instruct-4bit
            let dirName = "models--" + modelName.replacingOccurrences(of: "/", with: "--")
            let fullPath = (hubCache as NSString).appendingPathComponent(dirName)

            guard fileManager.fileExists(atPath: fullPath) else { continue }

            do {
                let size = Self.directorySize(at: fullPath)
                let sizeStr = ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
                try fileManager.removeItem(atPath: fullPath)
                print("  Deleted \(modelName) (\(sizeStr))")
            } catch {
                print("  Failed to delete \(modelName): \(error.localizedDescription)")
            }
        }
    }

    /// Calculate total size of a directory recursively
    internal static func directorySize(at path: String) -> UInt64 {
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(atPath: path) else { return 0 }

        var totalSize: UInt64 = 0
        while let file = enumerator.nextObject() as? String {
            let fullPath = (path as NSString).appendingPathComponent(file)
            if let attrs = try? fileManager.attributesOfItem(atPath: fullPath),
               let fileSize = attrs[.size] as? UInt64 {
                totalSize += fileSize
            }
        }
        return totalSize
    }
}
