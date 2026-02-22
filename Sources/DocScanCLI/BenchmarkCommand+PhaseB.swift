import AppKit
import ArgumentParser
import DocScanCore
import Foundation

// MARK: - Phase B: Model Discovery

extension BenchmarkCommand {
    /// Phase B: Discover alternative model pairs from Hugging Face
    func runPhaseB(
        configuration: Configuration,
        apiToken: String?
    ) async throws -> [ModelPair]? {
        printBenchmarkPhaseHeader("B", title: "Model Discovery")

        let client = HuggingFaceClient(apiToken: apiToken)
        var requestCount = 50

        while true {
            let pairs = try await discoverAndDisplayPairs(
                client: client, configuration: configuration, count: requestCount
            )

            guard let choice = TerminalUtils.menu(
                "How would you like to proceed?",
                options: [
                    "Benchmark these pairs",
                    "Request 100 model pairs",
                    "Skip model discovery",
                ]
            ) else {
                return nil
            }

            switch choice {
            case 0: return pairs
            case 1:
                requestCount = 100
                print()
                continue
            default: return nil
            }
        }
    }

    /// Discover model pairs, check for gated models, and let the user handle them
    private func discoverAndDisplayPairs(
        client: HuggingFaceClient,
        configuration: Configuration,
        count: Int
    ) async throws -> [ModelPair] {
        print("Searching for alternative MLX model pairs on Hugging Face...")
        print()

        var pairs = try await client.discoverModelPairs(
            currentVLM: configuration.modelName,
            currentTextLLM: configuration.textModelName,
            count: count
        )

        print("Discovered \(pairs.count) model pairs:")
        for (index, pair) in pairs.enumerated() {
            let current = (pair.vlmModelName == configuration.modelName
                && pair.textModelName == configuration.textModelName) ? " (current)" : ""
            print("  [\(index + 1)] VLM: \(pair.vlmModelName)")
            print("       Text: \(pair.textModelName)\(current)")
            print()
        }

        // Check for gated models and collect unique gated model IDs
        var gatedModelIds: Set<String> = []
        for pair in pairs {
            if await (try? client.isModelGated(pair.vlmModelName)) == true {
                gatedModelIds.insert(pair.vlmModelName)
            }
            if await (try? client.isModelGated(pair.textModelName)) == true {
                gatedModelIds.insert(pair.textModelName)
            }
        }

        if !gatedModelIds.isEmpty {
            pairs = try promptForGatedModels(gatedModelIds: gatedModelIds, pairs: pairs)
        }

        return pairs
    }

    /// Prompt user to handle gated models: remove affected pairs or open browser to accept licenses
    private func promptForGatedModels(
        gatedModelIds: Set<String>,
        pairs: [ModelPair]
    ) throws -> [ModelPair] {
        let affectedCount = pairs.count(where: { pair in
            gatedModelIds.contains(pair.vlmModelName) || gatedModelIds.contains(pair.textModelName)
        })

        print("⚠️  Found \(gatedModelIds.count) gated model(s) affecting \(affectedCount) pair(s):")
        for modelId in gatedModelIds.sorted() {
            print("     \(modelId)")
            print("     \(HuggingFaceClient.modelURL(for: modelId))")
        }
        print()

        guard let choice = TerminalUtils.menu(
            "Gated models require license approval on Hugging Face. How to proceed?",
            options: [
                "Remove pairs with gated models",
                "Open license pages in browser, then keep all pairs",
                "Keep all pairs (may fail during benchmark)",
            ]
        ) else {
            throw ExitCode.success
        }

        switch choice {
        case 0:
            let filtered = pairs.filter { pair in
                !gatedModelIds.contains(pair.vlmModelName) && !gatedModelIds.contains(pair.textModelName)
            }
            print("Removed \(pairs.count - filtered.count) pair(s). \(filtered.count) remaining.")
            print()
            return filtered
        case 1:
            for modelId in gatedModelIds.sorted() {
                let urlString = HuggingFaceClient.modelURL(for: modelId)
                if let url = URL(string: urlString) {
                    NSWorkspace.shared.open(url)
                }
            }
            print("Opened \(gatedModelIds.count) license page(s) in your browser.")
            print("Accept the licenses, then press Enter to continue...")
            _ = readLine()
            return pairs
        default:
            return pairs
        }
    }

    /// Phase B.1: Timeout selection
    func runPhaseB1() -> TimeInterval {
        printBenchmarkPhaseHeader("B.1", title: "Timeout Configuration")

        guard let choice = TerminalUtils.menu(
            "Select per-document timeout for benchmark runs:",
            options: [
                "10 seconds (strict)",
                "30 seconds (recommended)",
                "60 seconds (lenient)",
            ]
        ) else {
            print("Using default: 30 seconds")
            return 30
        }

        let timeouts: [TimeInterval] = [10, 30, 60]
        let selected = timeouts[choice]
        print("Timeout set to \(Int(selected)) seconds per document.")
        return selected
    }
}
