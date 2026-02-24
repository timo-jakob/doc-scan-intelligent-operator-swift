@preconcurrency import AppKit
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
    private let config: Configuration
    private let fileManager = FileManager.default

    // Chat session for VLM (lazy loaded)
    private var chatSession: ChatSession?
    private var loadedModel: ModelContext?
    private var currentModelName: String?

    public init(config: Configuration) {
        self.config = config
    }

    /// Generate text from image and prompt using VLM with ChatSession
    public func generateFromImage(
        _ image: NSImage,
        prompt: String,
        modelName: String? = nil
    ) async throws -> String {
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

        // Use ChatSession.respond with image parameter.
        // ChatSession is not Sendable-annotated yet, so we use nonisolated(unsafe)
        // to allow sending it to the nonisolated respond method.
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
            chatSession = ChatSession(model)
            currentModelName = modelName

            if config.verbose {
                print("VLM: Model loaded successfully")
            }
        } else if resetSession, let model = loadedModel {
            // Model already loaded, just create a fresh session (no expensive reload)
            if config.verbose {
                print("VLM: Creating fresh ChatSession (reusing cached model)")
            }
            chatSession = ChatSession(model)
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
        chatSession = ChatSession(model)
        currentModelName = modelName
    }

    /// Clear model cache
    public nonisolated func clearCache() throws {
        if FileManager.default.fileExists(atPath: config.modelCacheDir) {
            try FileManager.default.removeItem(atPath: config.modelCacheDir)
        }
    }
}
