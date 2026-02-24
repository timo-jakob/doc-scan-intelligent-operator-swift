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
        let documentResults = await processVLMDocuments(
            positivePDFs: positivePDFs,
            negativePDFs: negativePDFs,
            timeoutSeconds: timeoutSeconds,
            vlmFactory: vlmFactory
        )
        let elapsedSeconds = Date().timeIntervalSince(startTime)
        await vlmFactory.releaseVLM()

        return .from(
            modelName: modelName,
            documentResults: documentResults,
            elapsedSeconds: elapsedSeconds
        )
    }

    /// Process all documents, printing per-document progress dots
    private func processVLMDocuments(
        positivePDFs: [String],
        negativePDFs: [String],
        timeoutSeconds: TimeInterval,
        vlmFactory: VLMOnlyFactory
    ) async -> [VLMDocumentResult] {
        var results: [VLMDocumentResult] = []

        print("    ✓ ", terminator: "")
        fflush(stdout)
        for pdfPath in positivePDFs {
            let result = await benchmarkVLMDocument(
                pdfPath: pdfPath, isPositive: true,
                timeoutSeconds: timeoutSeconds, vlmFactory: vlmFactory
            )
            print(result.correct ? "." : "f", terminator: "")
            fflush(stdout)
            results.append(result)
        }

        print("  ✗ ", terminator: "")
        fflush(stdout)
        for pdfPath in negativePDFs {
            let result = await benchmarkVLMDocument(
                pdfPath: pdfPath, isPositive: false,
                timeoutSeconds: timeoutSeconds, vlmFactory: vlmFactory
            )
            print(result.correct ? "." : "f", terminator: "")
            fflush(stdout)
            results.append(result)
        }
        print("")

        return results
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

            // Run VLM with cooperative timeout + hard watchdog backstop
            let prompt = documentType.vlmPrompt
            let response = try await Self.withHardTimeout(seconds: timeoutSeconds * 2) {
                try await TimeoutError.withTimeout(seconds: timeoutSeconds) {
                    try await vlmProvider.generateFromImage(image, prompt: prompt)
                }
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
    /// Strips whitespace and punctuation, then checks for exact match or common prefixed forms.
    /// Returns `true` for "yes"/"ja" variants, `false` for everything else.
    static func parseYesNoResponse(_ response: String) -> Bool {
        let trimmed = response
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .trimmingCharacters(in: .punctuationCharacters)

        if trimmed == "yes" || trimmed == "ja" { return true }
        if trimmed.hasPrefix("yes,") || trimmed.hasPrefix("yes ") { return true }
        if trimmed.hasPrefix("ja,") || trimmed.hasPrefix("ja ") { return true }
        return false
    }
}
