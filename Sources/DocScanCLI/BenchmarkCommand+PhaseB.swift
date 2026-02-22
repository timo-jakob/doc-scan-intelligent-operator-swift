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
        var requestCount = 5

        while true {
            let pairs = try await discoverAndDisplayPairs(
                client: client, configuration: configuration, count: requestCount
            )

            guard let choice = TerminalUtils.menu(
                "How would you like to proceed?",
                options: [
                    "Benchmark these pairs",
                    "Request 10 different models",
                    "Skip model discovery",
                ]
            ) else {
                return nil
            }

            switch choice {
            case 0: return pairs
            case 1:
                requestCount = 10
                print()
                continue
            default: return nil
            }
        }
    }

    /// Discover model pairs and display them with gated-model warnings
    private func discoverAndDisplayPairs(
        client: HuggingFaceClient,
        configuration: Configuration,
        count: Int
    ) async throws -> [ModelPair] {
        print("Searching for alternative MLX model pairs on Hugging Face...")
        print()

        let pairs = try await client.discoverModelPairs(
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

        for pair in pairs {
            let vlmGated = try? await client.isModelGated(pair.vlmModelName)
            let textGated = try? await client.isModelGated(pair.textModelName)
            if vlmGated == true {
                print("  ⚠️  \(pair.vlmModelName) is gated — access approval may be required")
                print("     \(HuggingFaceClient.modelURL(for: pair.vlmModelName))")
            }
            if textGated == true {
                print("  ⚠️  \(pair.textModelName) is gated — access approval may be required")
                print("     \(HuggingFaceClient.modelURL(for: pair.textModelName))")
            }
        }

        return pairs
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
