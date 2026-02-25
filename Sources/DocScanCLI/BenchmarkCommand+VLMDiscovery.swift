import ArgumentParser
import DocScanCore
import Foundation

// MARK: - VLM Discovery & Recommendation

extension BenchmarkCommand {
    /// Resolve VLM models by querying HuggingFace for the given model family,
    /// or return a single concrete model if one is specified (contains `/`).
    /// Uses `--family` if provided, otherwise prompts interactively.
    func resolveVLMFamily(apiToken: String?) async throws -> [String] {
        let name: String
        if let family {
            let trimmed = family.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else {
                print("No model family provided.")
                throw ExitCode.failure
            }
            name = trimmed
        } else {
            guard let input = TerminalUtils.prompt(
                "Enter VLM model family (e.g. Qwen3-VL, FastVLM) or a concrete model:"
            ), !input.trimmingCharacters(in: .whitespaces).isEmpty else {
                print("No model family provided.")
                throw ExitCode.failure
            }
            name = input.trimmingCharacters(in: .whitespaces)
        }

        // A concrete model contains a "/" (e.g. "mlx-community/Qwen2-VL-2B-Instruct-4bit")
        if name.contains("/") {
            print("Using concrete model: \(name)")
            print()
            return [name]
        }

        print("Searching HuggingFace for MLX-compatible VLMs matching \"\(name)\"...")
        let client = HuggingFaceClient(apiToken: apiToken)
        let models = try await client.searchVLMFamily(name, limit: limit)

        guard !models.isEmpty else {
            print("No MLX-compatible VLM models found for \"\(name)\".")
            throw ExitCode.failure
        }

        print("Found \(models.count) model(s):")
        for (index, model) in models.enumerated() {
            let gatedLabel = model.isGated ? " (gated)" : ""
            print("  \(index + 1). \(model.modelId)\(gatedLabel)")
        }
        print()

        return models.map(\.modelId)
    }

    /// Prompt to update config with best VLM + best TextLLM
    func promptRecommendation(
        vlmResults: [VLMBenchmarkResult],
        textLLMResults: [TextLLMBenchmarkResult],
        configuration: Configuration
    ) throws {
        printBenchmarkPhaseHeader("Recommendation", title: "Best Models")

        let bestVLM = bestQualifyingResult(from: vlmResults)
        let bestTextLLM = bestQualifyingResult(from: textLLMResults)

        printBestModel(label: "VLM", result: bestVLM)
        printBestModel(label: "TextLLM", result: bestTextLLM)
        print()

        guard let vlm = bestVLM, let text = bestTextLLM else { return }

        if vlm.modelName == configuration.modelName,
           text.modelName == configuration.textModelName {
            print("Current configuration already uses the best models.")
            return
        }

        try promptConfigUpdate(
            bestVLMName: vlm.modelName, bestTextLLMName: text.modelName, configuration: configuration
        )
    }

    private func bestQualifyingResult<T: BenchmarkResultProtocol>(from results: [T]) -> T? {
        results.rankedByScore().first
    }

    private func printBestModel(label: String, result: (some BenchmarkResultProtocol)?) {
        if let result {
            print("Best \(label): \(result.modelName) (\(TerminalUtils.formatPercent(result.score)))")
        } else {
            print("Best \(label): No qualifying results")
        }
    }

    private func promptConfigUpdate(
        bestVLMName: String, bestTextLLMName: String, configuration: Configuration
    ) throws {
        guard let choice = TerminalUtils.menu(
            "Would you like to update your configuration?",
            options: [
                "Update config to use best VLM + best TextLLM",
                "Keep current configuration",
            ]
        ), choice == 0 else {
            print("Keeping current configuration.")
            return
        }

        var newConfig = configuration
        newConfig.modelName = bestVLMName
        newConfig.textModelName = bestTextLLMName

        let path = config ?? Configuration.defaultConfigPath
        try newConfig.save(to: path)
        print("Configuration saved to \(path)")
    }
}
