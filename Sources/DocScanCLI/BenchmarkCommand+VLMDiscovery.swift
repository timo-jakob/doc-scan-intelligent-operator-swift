import ArgumentParser
import DocScanCore
import Foundation

// MARK: - VLM Discovery & Recommendation

extension BenchmarkCommand {
    /// Resolve VLM models to benchmark. Accepts either a concrete HuggingFace
    /// model ID (e.g. "mlx-community/Qwen2-VL-2B-Instruct-4bit") or a family
    /// name (e.g. "Qwen3-VL") that triggers a HuggingFace discovery search.
    /// Uses `--model` (or `--family`) if provided, otherwise prompts interactively.
    func resolveVLMModels(apiToken: String?) async throws -> [String] {
        let noInputMessage = "No VLM model or family provided."
        let name: String
        if let model {
            let trimmed = model.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else {
                print(noInputMessage)
                throw ExitCode.failure
            }
            name = trimmed
        } else {
            guard let raw = TerminalUtils.prompt(
                "Enter VLM model family (e.g. Qwen3-VL, FastVLM) or a concrete model:"
            ) else {
                print(noInputMessage)
                throw ExitCode.failure
            }
            let trimmed = raw.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else {
                print(noInputMessage)
                throw ExitCode.failure
            }
            name = trimmed
        }

        if let resolved = VLMModelResolver.resolveImmediate(name) {
            print("Using concrete model: \(name)")
            print()
            return resolved
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
