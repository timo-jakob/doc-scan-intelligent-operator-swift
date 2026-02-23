import Foundation

/// Default model lists for independent benchmarking.
/// Curated from Hugging Face, filtered by MLX compatibility, popularity, and document-processing relevance.
public enum DefaultModelLists {
    /// Curated VLM models (true Vision-Language Models with image input support).
    /// Sourced from mlx-community, sorted roughly by popularity/relevance.
    public static let vlmModels: [String] = [
        // Qwen2-VL series (strong document understanding)
        "mlx-community/Qwen2-VL-2B-Instruct-4bit",
        "mlx-community/Qwen2-VL-2B-Instruct-8bit",
        "mlx-community/Qwen2-VL-7B-Instruct-4bit",
        "mlx-community/Qwen2-VL-7B-Instruct-8bit",
        "mlx-community/Qwen2.5-VL-3B-Instruct-4bit",
        "mlx-community/Qwen2.5-VL-3B-Instruct-8bit",
        "mlx-community/Qwen2.5-VL-7B-Instruct-4bit",
        "mlx-community/Qwen2.5-VL-7B-Instruct-8bit",
        // Pixtral (Mistral vision model)
        "mlx-community/pixtral-12b-2409-4bit",
        // InternVL2 series (document understanding)
        "mlx-community/InternVL2-1B-4bit",
        "mlx-community/InternVL2-2B-4bit",
        "mlx-community/InternVL2-4B-4bit",
        "mlx-community/InternVL2-8B-4bit",
        // Phi-3.5-vision
        "mlx-community/Phi-3.5-vision-instruct-4bit",
        // LLaVA series
        "mlx-community/llava-v1.6-mistral-7b-4bit",
        "mlx-community/llava-1.5-7b-4bit",
        // SmolVLM
        "mlx-community/SmolVLM-Instruct-bf16",
        "mlx-community/SmolVLM-256M-Instruct-4bit",
        "mlx-community/SmolVLM-500M-Instruct-4bit",
        // Paligemma (Google)
        "mlx-community/paligemma2-3b-pt-224-4bit",
        // Idefics
        "mlx-community/idefics2-8b-4bit",
        // Florence-2
        "mlx-community/Florence-2-large-4bit",
        // MiniCPM-V
        "mlx-community/MiniCPM-V-2_6-4bit",
        // Molmo
        "mlx-community/Molmo-7B-D-0924-4bit",
        // Deepseek-VL
        "mlx-community/deepseek-vl2-small-4bit",
    ]

    /// Curated TextLLM models (purely text-based, no multimodal models).
    /// Sourced from mlx-community, sorted roughly by popularity/relevance.
    public static let textLLMModels: [String] = [
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
