import AppKit
import DocScanCore
import Foundation

// MARK: - Phase A: Initial Benchmark Run + Sidecar Generation

extension BenchmarkCommand {
    /// Phase A: Run initial benchmark, generate sidecar files
    func runPhaseA(
        engine: BenchmarkEngine,
        positiveDir: String,
        negativeDir: String?
    ) async throws -> [ModelPairResult] {
        printBenchmarkPhaseHeader("A", title: "Initial Benchmark Run")
        print("Running current model pair against document corpus...")
        print()

        let results = try await engine.runInitialBenchmark(
            positiveDir: positiveDir,
            negativeDir: negativeDir
        )

        if let first = results.first {
            print("Initial run complete:")
            print("  Documents processed: \(first.documentResults.count)")
            print("  Accuracy: \(String(format: "%.1f%%", first.metrics.accuracy * 100))")
            print()

            for doc in first.documentResults {
                let status = doc.isFullyCorrect ? "✅" : "❌"
                let match = doc.predictedIsMatch ? "match" : "no match"
                print("  \(status) \(doc.filename) (\(match))")
            }
            print()
        }

        return results
    }

    /// Phase A.1: Verification pause — let user review sidecar files
    func runPhaseA1(positiveDir: String, negativeDir: String?) throws {
        printBenchmarkPhaseHeader("A.1", title: "Ground Truth Verification")

        print("JSON sidecar files have been generated next to each PDF.")
        print("Please review and correct them before continuing.")
        print()
        print("Sidecar locations:")

        let fm = FileManager.default
        let posContents = try fm.contentsOfDirectory(atPath: positiveDir)
        for file in posContents.sorted() where file.hasSuffix(".pdf.json") {
            let path = (positiveDir as NSString).appendingPathComponent(file)
            print("  \(path)")
        }

        if let negDir = negativeDir {
            let negContents = try fm.contentsOfDirectory(atPath: negDir)
            for file in negContents.sorted() where file.hasSuffix(".pdf.json") {
                let path = (negDir as NSString).appendingPathComponent(file)
                print("  \(path)")
            }
        }

        print()

        // Offer to open sidecar files
        if TerminalUtils.confirm("Open sidecar files in default editor?") {
            let sidecarDir = URL(fileURLWithPath: positiveDir)
            NSWorkspace.shared.open(sidecarDir)
        }

        print()
        print("After reviewing, press Enter to continue...")
        _ = readLine()
    }

    /// Phase A.2: Credential check for HF API
    func runPhaseA2() throws -> String? {
        printBenchmarkPhaseHeader("A.2", title: "Hugging Face Credentials")

        // Check Keychain first
        if let stored = try KeychainManager.retrieveToken(forAccount: "default") {
            print("Found existing Hugging Face token in Keychain.")
            if TerminalUtils.confirm("Use stored token?") {
                return stored
            }
        }

        print("A Hugging Face API token enables model discovery.")
        print("Without a token, only public models with no rate limiting.")
        print()

        guard let choice = TerminalUtils.menu(
            "How would you like to proceed?",
            options: [
                "Enter HF token (will be stored in Keychain)",
                "Skip (continue without token)",
            ]
        ) else {
            return nil
        }

        if choice == 0 {
            guard let token = TerminalUtils.promptMasked("Enter your Hugging Face token:"),
                  !token.isEmpty
            else {
                print("No token entered. Continuing without authentication.")
                return nil
            }
            try KeychainManager.saveToken(token, forAccount: "default")
            print("Token saved to Keychain.")
            return token
        }

        return nil
    }
}
