@preconcurrency import AppKit // TODO: Remove when NSImage is Sendable-annotated
import Foundation

// MARK: - VLM Benchmark

public extension BenchmarkEngine {
    /// Benchmark a single VLM model against all positive and negative documents
    func benchmarkVLM(
        modelName: String,
        positivePDFs: [String],
        negativePDFs: [String],
        timeoutSeconds: TimeInterval,
        vlmFactory: VLMOnlyFactory
    ) async -> VLMBenchmarkResult {
        // Release GPU resources from previous model
        await vlmFactory.releaseVLM()

        // Memory check
        let estimatedMB = Self.estimateMemoryMB(vlm: modelName, text: "")
        let availableMB = Self.availableMemoryMB()
        if estimatedMB > 0, availableMB > 0, estimatedMB > availableMB {
            if verbose {
                print("  Skipping: needs ~\(estimatedMB) MB, only \(availableMB) MB available")
            }
            return .disqualified(
                modelName: modelName,
                reason: "Insufficient memory (~\(estimatedMB) MB needed, \(availableMB) MB available)"
            )
        }

        // Preload model
        do {
            try await vlmFactory.preloadVLM(modelName: modelName, config: configuration)
        } catch {
            await vlmFactory.releaseVLM()
            return .disqualified(
                modelName: modelName,
                reason: "Failed to load model: \(error.localizedDescription)"
            )
        }

        let startTime = Date()
        var documentResults: [VLMDocumentResult] = []

        // Process positive documents
        for pdfPath in positivePDFs {
            let result = await benchmarkVLMDocument(
                pdfPath: pdfPath,
                isPositive: true,
                timeoutSeconds: timeoutSeconds,
                vlmFactory: vlmFactory
            )
            documentResults.append(result)
        }

        // Process negative documents
        for pdfPath in negativePDFs {
            let result = await benchmarkVLMDocument(
                pdfPath: pdfPath,
                isPositive: false,
                timeoutSeconds: timeoutSeconds,
                vlmFactory: vlmFactory
            )
            documentResults.append(result)
        }

        let elapsedSeconds = Date().timeIntervalSince(startTime)
        await vlmFactory.releaseVLM()

        return .from(
            modelName: modelName,
            documentResults: documentResults,
            elapsedSeconds: elapsedSeconds
        )
    }

    /// Benchmark a single document with VLM categorization
    private func benchmarkVLMDocument(
        pdfPath: String,
        isPositive: Bool,
        timeoutSeconds: TimeInterval,
        vlmFactory: VLMOnlyFactory
    ) async -> VLMDocumentResult {
        let filename = URL(fileURLWithPath: pdfPath).lastPathComponent

        do {
            // Convert PDF to image
            let image = try PDFUtils.pdfToImage(at: pdfPath, dpi: configuration.pdfDPI)

            guard let vlmProvider = await vlmFactory.makeVLMProvider() else {
                return VLMDocumentResult(
                    filename: filename,
                    isPositiveSample: isPositive,
                    predictedIsMatch: false
                )
            }

            // Run VLM with timeout
            let response = try await TimeoutError.withTimeout(seconds: timeoutSeconds) {
                try await vlmProvider.generateFromImage(image, prompt: self.documentType.vlmPrompt)
            }

            // Parse YES/NO response
            let predictedIsMatch = Self.parseYesNoResponse(response)

            return VLMDocumentResult(
                filename: filename,
                isPositiveSample: isPositive,
                predictedIsMatch: predictedIsMatch
            )
        } catch is TimeoutError {
            // Timeout scores 0 (does NOT disqualify the model)
            return VLMDocumentResult(
                filename: filename,
                isPositiveSample: isPositive,
                predictedIsMatch: !isPositive // Wrong answer = 0 points
            )
        } catch {
            // Error = 0 points (force incorrect prediction regardless of polarity)
            return VLMDocumentResult(
                filename: filename,
                isPositiveSample: isPositive,
                predictedIsMatch: !isPositive
            )
        }
    }

    /// Parse a YES/NO response from a VLM or TextLLM.
    ///
    /// Returns `true` when the response contains "yes" (case-insensitive) or starts with "ja" (German).
    /// All other responses — including empty strings, "no", and ambiguous text — return `false`.
    static func parseYesNoResponse(_ response: String) -> Bool {
        let lowercased = response.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        return lowercased.contains("yes") || lowercased.hasPrefix("ja")
    }
}
