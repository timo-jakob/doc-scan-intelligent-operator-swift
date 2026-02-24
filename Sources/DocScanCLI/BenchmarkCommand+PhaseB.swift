import AppKit
import ArgumentParser
import DocScanCore
import Foundation

// MARK: - Phase B: TextLLM Categorization + Extraction Benchmark

extension BenchmarkCommand {
    /// Phase B: Run each TextLLM model against all documents for categorization + extraction scoring.
    /// Each model runs in a subprocess so that MLX fatal errors are contained.
    func runPhaseB(
        engine: BenchmarkEngine,
        positivePDFs: [String],
        negativePDFs: [String],
        configuration: Configuration,
        timeoutSeconds: TimeInterval
    ) async throws -> [TextLLMBenchmarkResult] {
        printBenchmarkPhaseHeader("B", title: "TextLLM Categorization + Extraction Benchmark")

        let (groundTruths, ocrTexts) = try await prepareTextLLMData(
            engine: engine, positivePDFs: positivePDFs, negativePDFs: negativePDFs
        )

        let textLLMModels = configuration.benchmark.textLLMModels ?? DefaultModelLists.textLLMModels
        print("Evaluating \(textLLMModels.count) TextLLM model(s)")
        print("Documents: \(positivePDFs.count) positive, \(negativePDFs.count) negative")
        print("Timeout: \(Int(timeoutSeconds))s per inference")
        print()

        let runner = SubprocessRunner()
        var results: [TextLLMBenchmarkResult] = []

        for (index, modelName) in textLLMModels.enumerated() {
            print("[\(index + 1)/\(textLLMModels.count)] \(modelName)")

            let input = BenchmarkWorkerInput(
                phase: .textLLM,
                modelName: modelName,
                positivePDFs: positivePDFs,
                negativePDFs: negativePDFs,
                timeoutSeconds: timeoutSeconds,
                documentType: engine.documentType,
                configuration: configuration,
                verbose: verbose,
                ocrTexts: ocrTexts,
                groundTruths: groundTruths
            )

            let result: TextLLMBenchmarkResult = await runWorker(
                runner: runner, input: input, modelName: modelName,
                extractResult: { $0.textLLMResult },
                makeDisqualified: TextLLMBenchmarkResult.disqualified
            )
            printBenchmarkResult(result)
            results.append(result)
        }

        print(TerminalUtils.formatTextLLMLeaderboard(results: results))
        print()
        return results
    }

    private func prepareTextLLMData(
        engine: BenchmarkEngine,
        positivePDFs: [String],
        negativePDFs: [String]
    ) async throws -> (groundTruths: [String: GroundTruth], ocrTexts: [String: String]) {
        let (groundTruths, cachedOCRTexts) = try await manageGroundTruths(
            engine: engine,
            positivePDFs: positivePDFs,
            negativePDFs: negativePDFs,
            positiveDir: PathUtils.resolvePath(positiveDir),
            negativeDir: PathUtils.resolvePath(negativeDir)
        )

        let ocrTexts: [String: String]
        if let cachedOCRTexts {
            ocrTexts = cachedOCRTexts
            print("Reusing OCR text extracted during ground truth generation (\(ocrTexts.count) document(s))")
        } else {
            print("Pre-extracting OCR text from all documents...")
            ocrTexts = await engine.preExtractOCRTexts(
                positivePDFs: positivePDFs, negativePDFs: negativePDFs
            )
            print("  Extracted text from \(ocrTexts.count) document(s)")
        }
        print()

        return (groundTruths, ocrTexts)
    }
}

// MARK: - Ground Truth Management

private extension BenchmarkCommand {
    /// Manage ground truth JSON files — check for existing, prompt to reuse/regenerate, review.
    /// Returns ground truths and, when generation occurred, the OCR texts extracted during that pass.
    func manageGroundTruths(
        engine: BenchmarkEngine,
        positivePDFs: [String],
        negativePDFs: [String],
        positiveDir: String,
        negativeDir: String
    ) async throws -> (groundTruths: [String: GroundTruth], ocrTexts: [String: String]?) {
        let (needsGeneration, skipExisting) = try promptGroundTruthStrategy(
            engine: engine, positivePDFs: positivePDFs, negativePDFs: negativePDFs,
            positiveDir: positiveDir, negativeDir: negativeDir
        )

        var ocrTexts: [String: String]?
        if needsGeneration {
            ocrTexts = try await generateAndReviewGroundTruths(
                engine: engine, positivePDFs: positivePDFs, negativePDFs: negativePDFs,
                skipExisting: skipExisting
            )
        }

        let allPDFs = positivePDFs + negativePDFs
        let groundTruths = try engine.loadGroundTruths(pdfPaths: allPDFs)
        return (groundTruths, ocrTexts)
    }

    /// Check existing sidecars and prompt the user for reuse/regeneration strategy.
    /// Returns `(needsGeneration, skipExisting)`.
    func promptGroundTruthStrategy(
        engine: BenchmarkEngine,
        positivePDFs: [String],
        negativePDFs: [String],
        positiveDir: String,
        negativeDir: String
    ) throws -> (needsGeneration: Bool, skipExisting: Bool) {
        let existingMap = try engine.checkExistingSidecars(
            positiveDir: positiveDir, negativeDir: negativeDir
        )
        let existingCount = existingMap.filter(\.value).count
        let allPDFCount = positivePDFs.count + negativePDFs.count

        guard existingCount > 0 else { return (true, false) }

        print("Found \(existingCount)/\(allPDFCount) existing ground truth file(s).")
        print()

        guard let choice = TerminalUtils.menu(
            "How would you like to handle existing ground truth files?",
            options: [
                "Reuse existing (keep current ground truth)",
                "Regenerate all (overwrite with fresh results)",
            ]
        ) else {
            throw ExitCode.success
        }

        if choice == 0, existingCount == allPDFCount {
            print("Reusing all existing ground truth files.")
            print()
            return (false, false)
        } else if choice == 0 {
            print("Generating missing ground truth files (keeping existing)...")
            print()
            return (true, true)
        }
        return (true, false)
    }

    /// Generate ground truths and pause for user review. Returns the OCR texts for reuse.
    @discardableResult
    func generateAndReviewGroundTruths(
        engine: BenchmarkEngine,
        positivePDFs: [String],
        negativePDFs: [String],
        skipExisting: Bool
    ) async throws -> [String: String] {
        print("Generating ground truth files...")
        let ocrTexts = await engine.preExtractOCRTexts(
            positivePDFs: positivePDFs, negativePDFs: negativePDFs
        )
        _ = try await engine.generateGroundTruths(
            positivePDFs: positivePDFs, negativePDFs: negativePDFs, ocrTexts: ocrTexts,
            skipExisting: skipExisting
        )
        print()

        print("Ground truth JSON files have been generated next to each PDF.")
        print("Please review them before continuing.")
        print()
        let resolvedPositiveDir = PathUtils.resolvePath(positiveDir)
        let resolvedNegativeDir = PathUtils.resolvePath(negativeDir)
        await printAndOfferSidecars(positiveDir: resolvedPositiveDir, negativeDir: resolvedNegativeDir)

        print()
        print("After reviewing, press Enter to continue...")
        _ = readLine()

        return ocrTexts
    }

    /// Print sidecar locations and offer to open them in the default editor
    func printAndOfferSidecars(positiveDir: String, negativeDir: String) async {
        let fileManager = FileManager.default
        let posSidecars = sidecarPaths(in: positiveDir, fileManager: fileManager)
        let negSidecars = sidecarPaths(in: negativeDir, fileManager: fileManager)

        print("Sidecar locations:")
        for path in posSidecars + negSidecars {
            print("  \(path)")
        }
        print()

        if TerminalUtils.confirm("Open sidecar files in default editor?") {
            let allPaths = posSidecars + negSidecars
            await MainActor.run {
                for path in allPaths {
                    NSWorkspace.shared.open(URL(fileURLWithPath: path))
                }
            }
        }
    }

    func sidecarPaths(in directory: String, fileManager: FileManager) -> [String] {
        let contents = (try? fileManager.contentsOfDirectory(atPath: directory)) ?? []
        return contents.sorted()
            .filter { $0.hasSuffix(".pdf.json") }
            .map { (directory as NSString).appendingPathComponent($0) }
    }
}
