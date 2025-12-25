import Foundation
import MLX
import MLXNN
import MLXLLM
import MLXVLM
import MLXLMCommon
import AppKit

/// Manages Vision-Language Models using mlx-swift-lm
public class ModelManager {
    private let config: Configuration
    private let fileManager = FileManager.default

    // Chat session for VLM (lazy loaded)
    private var chatSession: ChatSession?
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

        // Use ChatSession.respond with image parameter
        let response = try await session.respond(
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
        // Check if model needs to be reloaded
        let needsReload = currentModelName != modelName || chatSession == nil

        if needsReload {
            if config.verbose {
                print("VLM: Loading model: \(modelName)")
            }

            // Load VLM using loadModel (recommended approach for VLMs)
            let model = try await loadModel(
                id: modelName
            ) { [self] progress in
                if self.config.verbose {
                    let percent = Int(progress.fractionCompleted * 100)
                    print("Downloading VLM: \(percent)%")
                }
            }

            // Create ChatSession for VLM inference
            chatSession = ChatSession(model)
            currentModelName = modelName

            if config.verbose {
                print("VLM: Model loaded successfully")
            }
        } else if resetSession, let currentName = currentModelName {
            // Model already loaded, but reset the session to clear conversation history
            if config.verbose {
                print("VLM: Resetting ChatSession to clear history")
            }
            // Reload the model to get a fresh session
            let model = try await loadModel(id: currentName)
            chatSession = ChatSession(model)
        }
    }

    /// Clear model cache
    public func clearCache() throws {
        if fileManager.fileExists(atPath: config.modelCacheDir) {
            try fileManager.removeItem(atPath: config.modelCacheDir)
        }
    }
}
