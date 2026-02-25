import Foundation

// MARK: - Model Cache Cleanup

public extension BenchmarkEngine {
    /// Remove cached models that were downloaded during benchmarking but are not the final selected model.
    /// - Parameters:
    ///   - modelNames: All model names that were benchmarked
    ///   - keepModel: Model name to keep (final selected); nil to delete all
    ///   - cachePath: Override for the HuggingFace hub cache path. Pass `nil` (default)
    ///     to resolve automatically via environment variables.
    func cleanupBenchmarkedModels(
        modelNames: [String],
        keepModel: String?,
        cachePath: String? = nil
    ) {
        let keepModels: Set<String> = keepModel.map { [$0] } ?? []

        let benchmarkedModels = Set(modelNames)
        let toDelete = benchmarkedModels.subtracting(keepModels)

        guard !toDelete.isEmpty else {
            print("No benchmark models to clean up.")
            return
        }

        let fileManager = FileManager.default
        let hubCache = cachePath ?? Self.huggingFaceCachePath()

        for modelName in toDelete.sorted() {
            guard VLMModelResolver.isConcreteModel(modelName) else {
                print("  Skipping invalid model name: \(modelName)")
                continue
            }
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

    /// Resolve the HuggingFace hub cache directory, respecting environment overrides.
    /// Checks HUGGINGFACE_HUB_CACHE, then HF_HOME/hub, then the default ~/.cache/huggingface/hub.
    ///
    /// - Parameter environment: Environment dictionary to read from. Defaults to
    ///   `ProcessInfo.processInfo.environment`. Pass a custom dictionary in tests
    ///   to avoid thread-unsafe `setenv`/`unsetenv` calls.
    internal static func huggingFaceCachePath(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> String {
        if let hubCache = environment["HUGGINGFACE_HUB_CACHE"] {
            return hubCache
        }
        if let hfHome = environment["HF_HOME"] {
            return (hfHome as NSString).appendingPathComponent("hub")
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".cache/huggingface/hub")
            .path
    }

    /// Calculate total size of a directory recursively
    internal static func directorySize(at path: String) -> UInt64 {
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(atPath: path) else { return 0 }

        var totalSize: UInt64 = 0
        for case let file as String in enumerator {
            let fullPath = (path as NSString).appendingPathComponent(file)
            if let attrs = try? fileManager.attributesOfItem(atPath: fullPath),
               let fileSize = attrs[.size] as? UInt64 {
                totalSize += fileSize
            }
        }
        return totalSize
    }
}
