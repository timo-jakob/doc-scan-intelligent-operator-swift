import AppKit
import ArgumentParser
import DocScanCore
import Foundation

// MARK: - Phase B: TextLLM Categorization + Extraction Benchmark

extension BenchmarkCommand {
    /// Phase B: Run each TextLLM model against all documents for categorization + extraction scoring
    func runPhaseB(
        engine: BenchmarkEngine,
        positivePDFs: [String],
        negativePDFs: [String],
        configuration: Configuration,
        timeoutSeconds: TimeInterval
    ) async throws -> [TextLLMBenchmarkResult] {
        printBenchmarkPhaseHeader("B", title: "TextLLM Categorization + Extraction Benchmark")

        let groundTruths = try await manageGroundTruths(
            engine: engine,
            positivePDFs: positivePDFs,
            negativePDFs: negativePDFs,
            positiveDir: PathUtils.resolvePath(positiveDir),
            negativeDir: PathUtils.resolvePath(negativeDir)
        )

        print("Pre-extracting OCR text from all documents...")
        let ocrTexts = await engine.preExtractOCRTexts(
            positivePDFs: positivePDFs, negativePDFs: negativePDFs
        )
        print("  Extracted text from \(ocrTexts.count) document(s)")
        print()

        let textLLMModels = configuration.benchmarkTextLLMModels ?? DefaultModelLists.textLLMModels
        print("Evaluating \(textLLMModels.count) TextLLM model(s)")
        print("Documents: \(positivePDFs.count) positive, \(negativePDFs.count) negative")
        print("Timeout: \(Int(timeoutSeconds))s per inference")
        print()

        let context = TextLLMBenchmarkContext(
            ocrTexts: ocrTexts, groundTruths: groundTruths,
            timeoutSeconds: timeoutSeconds, textLLMFactory: DefaultTextLLMOnlyFactory()
        )
        var results: [TextLLMBenchmarkResult] = []

        for (index, modelName) in textLLMModels.enumerated() {
            print("[\(index + 1)/\(textLLMModels.count)] \(modelName)")

            let result = await engine.benchmarkTextLLM(
                modelName: modelName,
                positivePDFs: positivePDFs, negativePDFs: negativePDFs,
                context: context
            )

            printTextLLMResult(result)
            results.append(result)
        }

        print(TerminalUtils.formatTextLLMLeaderboard(results: results))
        print()
        return results
    }

    private func printTextLLMResult(_ result: TextLLMBenchmarkResult) {
        if result.isDisqualified {
            print("  DISQUALIFIED: \(result.disqualificationReason ?? "Unknown")")
        } else {
            let scoreStr = String(format: "%.1f%%", result.score * 100)
            let points = "\(result.totalScore)/\(result.maxScore)"
            let time = String(format: "%.1fs", result.elapsedSeconds)
            print("  Score: \(scoreStr) (\(points)) in \(time)")
        }
        print()
    }
}

// MARK: - Ground Truth Management

private extension BenchmarkCommand {
    /// Manage ground truth JSON files — check for existing, prompt to reuse/regenerate, review
    func manageGroundTruths(
        engine: BenchmarkEngine,
        positivePDFs: [String],
        negativePDFs: [String],
        positiveDir: String,
        negativeDir: String
    ) async throws -> [String: GroundTruth] {
        let needsGeneration = try promptGroundTruthStrategy(
            engine: engine, positivePDFs: positivePDFs, negativePDFs: negativePDFs,
            positiveDir: positiveDir, negativeDir: negativeDir
        )

        if needsGeneration {
            try await generateAndReviewGroundTruths(
                engine: engine, positivePDFs: positivePDFs, negativePDFs: negativePDFs,
                positiveDir: positiveDir, negativeDir: negativeDir
            )
        }

        let allPDFs = positivePDFs + negativePDFs
        return try engine.loadGroundTruths(pdfPaths: allPDFs)
    }

    /// Check existing sidecars and prompt the user for reuse/regeneration strategy
    func promptGroundTruthStrategy(
        engine: BenchmarkEngine,
        positivePDFs: [String],
        negativePDFs: [String],
        positiveDir: String,
        negativeDir: String
    ) throws -> Bool {
        let existingMap = try engine.checkExistingSidecars(
            positiveDir: positiveDir, negativeDir: negativeDir
        )
        let existingCount = existingMap.filter(\.value).count
        let allPDFCount = positivePDFs.count + negativePDFs.count

        guard existingCount > 0 else { return true }

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
            return false
        } else if choice == 0 {
            print("Regenerating missing ground truth files...")
            print()
        }
        return true
    }

    /// Generate ground truths and pause for user review
    func generateAndReviewGroundTruths(
        engine: BenchmarkEngine,
        positivePDFs: [String],
        negativePDFs: [String],
        positiveDir: String,
        negativeDir: String
    ) async throws {
        print("Generating ground truth files...")
        let ocrTexts = await engine.preExtractOCRTexts(
            positivePDFs: positivePDFs, negativePDFs: negativePDFs
        )
        _ = try await engine.generateGroundTruths(
            positivePDFs: positivePDFs, negativePDFs: negativePDFs, ocrTexts: ocrTexts
        )
        print()

        print("Ground truth JSON files have been generated next to each PDF.")
        print("Please review them before continuing.")
        print()
        await printAndOfferSidecars(positiveDir: positiveDir, negativeDir: negativeDir)

        print()
        print("After reviewing, press Enter to continue...")
        _ = readLine()
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
