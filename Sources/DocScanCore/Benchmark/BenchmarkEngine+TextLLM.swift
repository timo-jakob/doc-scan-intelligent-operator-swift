import Foundation

// MARK: - TextLLM Benchmark Context

/// Groups the shared parameters for a TextLLM benchmark run, including
/// pre-extracted OCR texts, ground truths, and the factory to create TextLLM instances.
public struct TextLLMBenchmarkContext: Sendable {
    /// Pre-extracted OCR texts keyed by PDF path
    public let ocrTexts: [String: String]
    /// Expected ground truth values keyed by PDF path
    public let groundTruths: [String: GroundTruth]
    /// Timeout in seconds for each individual inference call
    public let timeoutSeconds: TimeInterval
    /// Factory for creating TextLLM instances per model
    public let textLLMFactory: TextLLMOnlyFactory

    public init(
        ocrTexts: [String: String],
        groundTruths: [String: GroundTruth],
        timeoutSeconds: TimeInterval,
        textLLMFactory: TextLLMOnlyFactory
    ) {
        self.ocrTexts = ocrTexts
        self.groundTruths = groundTruths
        self.timeoutSeconds = timeoutSeconds
        self.textLLMFactory = textLLMFactory
    }
}

// MARK: - TextLLM Benchmark

public extension BenchmarkEngine {
    /// Benchmark a single TextLLM model against all positive and negative documents
    func benchmarkTextLLM(
        modelName: String,
        positivePDFs: [String],
        negativePDFs: [String],
        context: TextLLMBenchmarkContext
    ) async -> TextLLMBenchmarkResult {
        if let earlyResult = await prepareTextLLM(modelName: modelName, context: context) {
            return earlyResult
        }

        let startTime = Date()
        var documentResults: [TextLLMDocumentResult] = []

        for pdfPath in positivePDFs {
            let result = await benchmarkTextLLMDocument(pdfPath: pdfPath, isPositive: true, context: context)
            documentResults.append(result)
        }

        for pdfPath in negativePDFs {
            let result = await benchmarkTextLLMDocument(pdfPath: pdfPath, isPositive: false, context: context)
            documentResults.append(result)
        }

        let elapsedSeconds = Date().timeIntervalSince(startTime)
        await context.textLLMFactory.releaseTextLLM()

        return .from(modelName: modelName, documentResults: documentResults, elapsedSeconds: elapsedSeconds)
    }
}

// MARK: - Private Helpers

private extension BenchmarkEngine {
    /// Release previous model, check memory, preload new model. Returns a disqualified result on failure.
    func prepareTextLLM(
        modelName: String,
        context: TextLLMBenchmarkContext
    ) async -> TextLLMBenchmarkResult? {
        await context.textLLMFactory.releaseTextLLM()

        let estimatedMB = Self.estimateMemoryMB(vlm: "", text: modelName)
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

        do {
            try await context.textLLMFactory.preloadTextLLM(modelName: modelName, config: configuration)
        } catch {
            await context.textLLMFactory.releaseTextLLM()
            return .disqualified(
                modelName: modelName,
                reason: "Failed to load model: \(error.localizedDescription)"
            )
        }

        return nil
    }

    /// Benchmark a single document with TextLLM categorization + extraction
    func benchmarkTextLLMDocument(
        pdfPath: String,
        isPositive: Bool,
        context: TextLLMBenchmarkContext
    ) async -> TextLLMDocumentResult {
        let filename = URL(fileURLWithPath: pdfPath).lastPathComponent

        guard let ocrText = context.ocrTexts[pdfPath], !ocrText.isEmpty else {
            return TextLLMDocumentResult(
                filename: filename, isPositiveSample: isPositive,
                categorizationCorrect: false, extractionCorrect: false
            )
        }

        guard let textLLM = await context.textLLMFactory.makeTextLLMProvider() else {
            return TextLLMDocumentResult(
                filename: filename, isPositiveSample: isPositive,
                categorizationCorrect: false, extractionCorrect: false
            )
        }

        let predictedIsMatch = await categorizeWithTextLLM(
            ocrText: ocrText, textLLM: textLLM, timeoutSeconds: context.timeoutSeconds
        )

        guard let predicted = predictedIsMatch else {
            return TextLLMDocumentResult(
                filename: filename, isPositiveSample: isPositive,
                categorizationCorrect: false, extractionCorrect: false
            )
        }

        let categorizationCorrect = (isPositive == predicted)

        if !isPositive {
            return TextLLMDocumentResult(
                filename: filename, isPositiveSample: false,
                categorizationCorrect: categorizationCorrect,
                extractionCorrect: categorizationCorrect
            )
        }

        guard categorizationCorrect else {
            return TextLLMDocumentResult(
                filename: filename, isPositiveSample: true,
                categorizationCorrect: false, extractionCorrect: false
            )
        }

        let extractionCorrect = await scoreExtraction(
            pdfPath: pdfPath, ocrText: ocrText, textLLM: textLLM, context: context
        )
        return TextLLMDocumentResult(
            filename: filename, isPositiveSample: true,
            categorizationCorrect: true, extractionCorrect: extractionCorrect
        )
    }

    /// Categorize a document using the TextLLM. Returns nil on timeout/error.
    func categorizeWithTextLLM(
        ocrText: String,
        textLLM: any TextLLMProviding,
        timeoutSeconds: TimeInterval
    ) async -> Bool? {
        let prompt = documentType.textCategorizationPrompt
        do {
            let response = try await TimeoutError.withTimeout(seconds: timeoutSeconds) {
                try await textLLM.generate(
                    systemPrompt: "You are a document classification assistant. Answer only YES or NO.",
                    userPrompt: prompt + "\n\nDocument text:\n" + ocrText,
                    maxTokens: 10
                )
            }
            return Self.parseYesNoResponse(response)
        } catch {
            return nil
        }
    }

    /// Score extraction against ground truth. Returns whether extraction was correct.
    func scoreExtraction(
        pdfPath: String,
        ocrText: String,
        textLLM: any TextLLMProviding,
        context: TextLLMBenchmarkContext
    ) async -> Bool {
        guard let groundTruth = context.groundTruths[pdfPath] else {
            return false
        }

        let docType = documentType
        do {
            let extraction = try await TimeoutError.withTimeout(seconds: context.timeoutSeconds) {
                try await textLLM.extractData(for: docType, from: ocrText)
            }

            var actualDate: String?
            if let extractedDate = extraction.date {
                actualDate = DateUtils.formatDate(extractedDate)
            }

            let scoring = FuzzyMatcher.scoreDocument(
                expected: groundTruth,
                actualIsMatch: true,
                actualDate: actualDate,
                actualSecondaryField: extraction.secondaryField,
                actualPatientName: extraction.patientName
            )
            return scoring.extractionCorrect
        } catch {
            return false
        }
    }
}
