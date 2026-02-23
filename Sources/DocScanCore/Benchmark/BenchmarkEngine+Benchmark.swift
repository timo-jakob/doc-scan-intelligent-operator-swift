import Foundation

// MARK: - Benchmark a Model Pair

public extension BenchmarkEngine {
    /// Benchmark a specific model pair against verified ground truths
    func benchmarkModelPair(
        _ pair: ModelPair,
        pdfPaths: [String],
        groundTruths: [String: GroundTruth],
        timeoutSeconds: TimeInterval = 30
    ) async throws -> ModelPairResult {
        // Release GPU resources from previous model pair to prevent Metal resource exhaustion
        await detectorFactory.releaseModels()

        if let memoryDQ = checkMemory(for: pair) {
            return memoryDQ
        }

        var pairConfig = configuration
        pairConfig.modelName = pair.vlmModelName
        pairConfig.textModelName = pair.textModelName

        // Pre-download and load models; catch resource limit errors gracefully
        do {
            try await detectorFactory.preloadModels(config: pairConfig)
        } catch {
            await detectorFactory.releaseModels()
            return disqualifiedResult(
                pair, reason: "Failed to load models: \(error.localizedDescription)"
            )
        }

        return try await benchmarkDocuments(
            pair: pair, pdfPaths: pdfPaths,
            groundTruths: groundTruths, config: pairConfig,
            timeoutSeconds: timeoutSeconds
        )
    }
}

// MARK: - Private Benchmark Helpers

private extension BenchmarkEngine {
    /// Pre-flight memory check — returns a disqualified result if the pair would exhaust memory
    func checkMemory(for pair: ModelPair) -> ModelPairResult? {
        let estimatedMB = Self.estimateMemoryMB(vlm: pair.vlmModelName, text: pair.textModelName)
        let availableMB = Self.availableMemoryMB()
        guard estimatedMB > 0, availableMB > 0, estimatedMB > availableMB else {
            return nil
        }
        if verbose {
            print("Skipping \(pair.vlmModelName) + \(pair.textModelName): "
                + "needs ~\(estimatedMB) MB, only \(availableMB) MB available")
        }
        return disqualifiedResult(
            pair, reason: "Insufficient memory (~\(estimatedMB) MB needed, \(availableMB) MB available)"
        )
    }

    func disqualifiedResult(_ pair: ModelPair, reason: String) -> ModelPairResult {
        ModelPairResult(
            vlmModelName: pair.vlmModelName,
            textModelName: pair.textModelName,
            metrics: BenchmarkMetrics.compute(from: []),
            documentResults: [],
            isDisqualified: true,
            disqualificationReason: reason
        )
    }

    func benchmarkDocuments(
        pair: ModelPair, pdfPaths: [String],
        groundTruths: [String: GroundTruth], config: Configuration,
        timeoutSeconds: TimeInterval
    ) async throws -> ModelPairResult {
        var documentResults: [DocumentResult] = []
        let totalDocs = pdfPaths.count

        for (docIndex, pdfPath) in pdfPaths.enumerated() {
            let filename = URL(fileURLWithPath: pdfPath).lastPathComponent
            guard let truth = groundTruths[pdfPath] else {
                print("    [\(docIndex + 1)/\(totalDocs)] \(filename) — Skipped (no ground truth)")
                continue
            }

            print("    [\(docIndex + 1)/\(totalDocs)] \(filename) — Categorizing...", terminator: "")
            fflush(stdout)

            do {
                let result = try await TimeoutError.withTimeout(seconds: timeoutSeconds) {
                    try await self.processSingleDocument(
                        pdfPath: pdfPath,
                        config: config,
                        groundTruth: truth
                    )
                }
                documentResults.append(result)
            } catch is TimeoutError {
                print(" Timeout")
                return ModelPairResult(
                    vlmModelName: pair.vlmModelName,
                    textModelName: pair.textModelName,
                    metrics: BenchmarkMetrics.compute(from: documentResults),
                    documentResults: documentResults,
                    isDisqualified: true,
                    disqualificationReason: "Exceeded \(Int(timeoutSeconds))s timeout on \(filename)"
                )
            } catch {
                print(" Error: \(error.localizedDescription)")
                documentResults.append(DocumentResult(
                    filename: filename,
                    isPositiveSample: truth.isMatch,
                    predictedIsMatch: false,
                    documentScore: 0
                ))
            }
        }

        let metrics = BenchmarkMetrics.compute(from: documentResults)
        return ModelPairResult(
            vlmModelName: pair.vlmModelName,
            textModelName: pair.textModelName,
            metrics: metrics,
            documentResults: documentResults
        )
    }

    func processSingleDocument(
        pdfPath: String,
        config: Configuration,
        groundTruth: GroundTruth
    ) async throws -> DocumentResult {
        let filename = URL(fileURLWithPath: pdfPath).lastPathComponent
        let detector = try await detectorFactory.makeDetector(
            config: config, documentType: documentType
        )
        let categorization = try await detector.categorize(pdfPath: pdfPath)
        let isMatch = categorization.agreedIsMatch ?? categorization.vlmResult.isMatch
        let categorizationCorrect = (groundTruth.isMatch == isMatch)
        print(" \(categorizationCorrect ? "✓" : "✗")", terminator: "")
        fflush(stdout)

        var actualDate: String?
        var actualSecondaryField: String?
        var actualPatientName: String?

        if isMatch {
            print(" Extracting...", terminator: "")
            fflush(stdout)
            let extraction = try await detector.extractData()
            if let extractedDate = extraction.date {
                actualDate = DateUtils.formatDate(extractedDate)
            }
            actualSecondaryField = extraction.secondaryField
            actualPatientName = extraction.patientName
        }

        let scoring = FuzzyMatcher.scoreDocument(
            expected: groundTruth,
            actualIsMatch: isMatch,
            actualDate: actualDate,
            actualSecondaryField: actualSecondaryField,
            actualPatientName: actualPatientName
        )

        if isMatch, categorizationCorrect {
            print(" \(scoring.extractionCorrect ? "✓" : "✗")", terminator: "")
        }
        print(" [\(scoring.score)/2]")

        return DocumentResult(
            filename: filename,
            isPositiveSample: groundTruth.isMatch,
            predictedIsMatch: isMatch,
            documentScore: scoring.score
        )
    }
}
