import Foundation

/// Default model lists for independent benchmarking.
/// VLM models are discovered dynamically via HuggingFace API (see --family).
/// TextLLM models are curated from Hugging Face, filtered by MLX compatibility and relevance.
package enum DefaultModelLists {
    /// Curated TextLLM models (purely text-based, no multimodal models).
    /// Sourced from mlx-community, sorted roughly by popularity/relevance.
    package static let textLLMModels: [String] = [
        // Qwen2.5 series (strong instruction following)
        "mlx-community/Qwen2.5-7B-Instruct-4bit",
        "mlx-community/Qwen2.5-7B-Instruct-8bit",
        "mlx-community/Qwen2.5-3B-Instruct-4bit",
        "mlx-community/Qwen2.5-3B-Instruct-8bit",
        "mlx-community/Qwen2.5-1.5B-Instruct-4bit",
        "mlx-community/Qwen2.5-14B-Instruct-4bit",
        // Llama 3.x series (Meta)
        "mlx-community/Meta-Llama-3.1-8B-Instruct-4bit",
        "mlx-community/Meta-Llama-3.1-8B-Instruct-8bit",
        "mlx-community/Llama-3.2-3B-Instruct-4bit",
        "mlx-community/Llama-3.2-1B-Instruct-4bit",
        // Mistral / Mixtral
        "mlx-community/Mistral-7B-Instruct-v0.3-4bit",
        "mlx-community/Mistral-Nemo-Instruct-2407-4bit",
        // Phi series (Microsoft)
        "mlx-community/Phi-3.5-mini-instruct-4bit",
        "mlx-community/Phi-3-mini-4k-instruct-4bit",
        // Gemma (Google)
        "mlx-community/gemma-2-9b-it-4bit",
        "mlx-community/gemma-2-2b-it-4bit",
        // SmolLM (HuggingFace)
        "mlx-community/SmolLM2-1.7B-Instruct-4bit",
        "mlx-community/SmolLM2-360M-Instruct-4bit",
        // Yi (01.AI)
        "mlx-community/Yi-1.5-9B-Chat-4bit",
        // InternLM
        "mlx-community/internlm2_5-7b-chat-4bit",
        // Deepseek
        "mlx-community/DeepSeek-R1-Distill-Qwen-7B-4bit",
        // StarCoder2 (code but good at structured extraction)
        "mlx-community/starcoder2-7b-4bit",
        // Command-R (Cohere)
        "mlx-community/c4ai-command-r7b-12-2024-4bit",
        // OLMo (AI2)
        "mlx-community/OLMo-2-0325-32B-Instruct-4bit",
    ]
}
