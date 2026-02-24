@preconcurrency import AppKit // TODO: Remove when NSImage is Sendable-annotated
import Foundation
import MLX
import MLXLLM
import MLXLMCommon
import MLXNN
import MLXVLM

// MARK: - VLM Provider Protocol

/// Protocol for Vision-Language Model providers
/// Enables dependency injection and testing without actual VLM models
public protocol VLMProvider: Sendable {
    /// Generate text from image and prompt using VLM
    func generateFromImage(
        _ image: NSImage,
        prompt: String,
        modelName: String?
    ) async throws -> String
}

/// Default parameter extension
public extension VLMProvider {
    func generateFromImage(_ image: NSImage, prompt: String) async throws -> String {
        try await generateFromImage(image, prompt: prompt, modelName: nil)
    }
}

// MARK: - Model Manager

/// Manages Vision-Language Models using mlx-swift-lm
public actor ModelManager: VLMProvider {
    nonisolated let config: Configuration
    private let fileManager = FileManager.default

    /// System prompt used to frame the VLM's behavior for classification tasks.
    private static let classifierInstructions =
        "You are a document classifier. " +
        "Analyze the image and answer the question with exactly one word: YES or NO. " +
        "Do not explain your reasoning."

    /// Generation parameters optimized for YES/NO classification.
    /// - maxTokens: 8 (only need a single word)
    /// - temperature: 0 (deterministic output)
    private static let classificationParams = GenerateParameters(
        maxTokens: 8,
        temperature: 0.0
    )

    /// Image processing that preserves A4 portrait aspect ratio (1:√2).
    /// The default 512×512 squashes A4 documents; 448×632 keeps layout readable.
    private static let a4Processing = UserInput.Processing(
        resize: CGSize(width: 448, height: 632)
    )

    // Chat session for VLM (lazy loaded)
    private var chatSession: ChatSession?
    private var loadedModel: ModelContext?
    private var currentModelName: String?
    private var isGenerating = false

    public init(config: Configuration) {
        self.config = config
    }

    /// Generate text from image and prompt using VLM with ChatSession
    public func generateFromImage(
        _ image: NSImage,
        prompt: String,
        modelName: String? = nil
    ) async throws -> String {
        guard !isGenerating else {
            throw DocScanError.inferenceError("VLM generation already in progress")
        }
        isGenerating = true
        defer { isGenerating = false }

        let model = modelName ?? config.modelName

        if config.verbose {
            print("VLM: Using model: \(model)")
            print("VLM: Prompt: \(prompt)")
        }

        // Load model and create FRESH chat session (reset for each image to avoid conversation history contamination)
        try await loadModelIfNeeded(modelName: model, resetSession: true)

        guard let session = chatSession else {
            throw DocScanError.modelLoadFailed("ChatSession not initialized")
        }

        // Save NSImage to temporary file (required for ChatSession API)
        let tempURL = try saveImageToTemp(image)
        defer {
            try? fileManager.removeItem(at: tempURL)
        }

        if config.verbose {
            print("VLM: Sending prompt with image...")
        }

        // SAFETY: ChatSession is not yet Sendable-annotated in mlx-swift-lm.
        // This is safe because:
        // 1. We create a fresh session per generateFromImage call (resetSession: true above)
        // 2. The isGenerating reentrancy guard prevents concurrent access
        // 3. The session is never shared outside this actor
        // TODO: Remove nonisolated(unsafe) when mlx-swift-lm adopts Sendable
        nonisolated(unsafe) let sendableSession = session
        let response = try await sendableSession.respond(
            to: prompt,
            image: .url(tempURL)
        )

        if config.verbose {
            print("VLM: Response received")
        }

        return response
    }

    /// Save NSImage to temporary file for VLM processing
    private func saveImageToTemp(_ image: NSImage) throws -> URL {
        let tempDir = fileManager.temporaryDirectory
        let tempURL = tempDir.appendingPathComponent(UUID().uuidString + ".png")

        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw DocScanError.pdfConversionFailed("Unable to convert NSImage to CGImage")
        }

        let bitmapRep = NSBitmapImageRep(cgImage: cgImage)
        guard let pngData = bitmapRep.representation(using: .png, properties: [:]) else {
            throw DocScanError.pdfConversionFailed("Unable to convert image to PNG")
        }

        try pngData.write(to: tempURL)
        return tempURL
    }

    /// Create a new ChatSession with the classifier system prompt, generation params, and A4 image processing.
    private func makeSession(_ model: ModelContext) -> ChatSession {
        ChatSession(
            model,
            instructions: Self.classifierInstructions,
            generateParameters: Self.classificationParams,
            processing: Self.a4Processing
        )
    }

    /// Load VLM model and create ChatSession if not already loaded
    private func loadModelIfNeeded(modelName: String, resetSession: Bool = false) async throws {
        // Check if model needs to be reloaded (different model or no model loaded)
        let needsReload = currentModelName != modelName || loadedModel == nil

        if needsReload {
            if config.verbose {
                print("VLM: Loading model: \(modelName)")
            }

            // Load VLM using loadModel (recommended approach for VLMs)
            let model = try await loadModel(
                id: modelName
            ) { [self] progress in
                if config.verbose {
                    let percent = Int(progress.fractionCompleted * 100)
                    print("Downloading VLM: \(percent)%")
                }
            }

            // Cache the loaded model and create ChatSession
            loadedModel = model
            chatSession = makeSession(model)
            currentModelName = modelName

            if config.verbose {
                print("VLM: Model loaded successfully")
            }
        } else if resetSession, let model = loadedModel {
            // Model already loaded, just create a fresh session (no expensive reload)
            if config.verbose {
                print("VLM: Creating fresh ChatSession (reusing cached model)")
            }
            chatSession = makeSession(model)
        }
    }

    /// Preload the VLM model so it is ready before processing begins.
    /// Calls progressHandler with fractions 0.0–1.0 only when a download is required.
    /// If the model is already cached locally the handler is never called.
    public func preload(
        modelName: String,
        progressHandler: @escaping @Sendable (Double) -> Void
    ) async throws {
        guard loadedModel == nil || currentModelName != modelName else { return }

        let model = try await loadModel(id: modelName) { progress in
            progressHandler(progress.fractionCompleted)
        }

        loadedModel = model
        chatSession = makeSession(model)
        currentModelName = modelName
    }

    /// Clear model cache. Must not be called while model loading is in progress.
    public func clearCache() throws {
        if FileManager.default.fileExists(atPath: config.modelCacheDir) {
            try FileManager.default.removeItem(atPath: config.modelCacheDir)
        }
    }
}
