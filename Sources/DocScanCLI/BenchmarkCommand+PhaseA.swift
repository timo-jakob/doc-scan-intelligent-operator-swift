import AppKit
import ArgumentParser
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

        let existingMap = try engine.checkExistingSidecars(
            positiveDir: positiveDir, negativeDir: negativeDir
        )
        let existingPaths = existingMap.filter(\.value).map(\.key).sorted()
        let skipPaths = try promptForExistingSidecars(existingPaths)

        print("Running current model pair against document corpus...")
        print()

        let results = try await engine.runInitialBenchmark(
            positiveDir: positiveDir,
            negativeDir: negativeDir,
            skipPaths: skipPaths
        )

        if let first = results.first {
            print("Initial run complete:")
            print("  Documents processed: \(first.documentResults.count)")
            print("  Score: \(String(format: "%.1f%%", first.metrics.score * 100))")
            print()

            for doc in first.documentResults {
                let icon = doc.documentScore == 2 ? "✅" : doc.documentScore == 1 ? "⚠️" : "❌"
                let match = doc.predictedIsMatch ? "match" : "no match"
                print("  \(icon) \(doc.filename) (\(match)) [\(doc.documentScore)/2]")
            }
            print()
        }

        return results
    }

    /// Prompt user about existing sidecar files, returning paths to skip
    private func promptForExistingSidecars(_ existingPaths: [String]) throws -> Set<String> {
        guard !existingPaths.isEmpty else { return [] }

        print("Found \(existingPaths.count) existing sidecar file(s):")
        for path in existingPaths {
            let filename = URL(fileURLWithPath: path).lastPathComponent
            print("  \(filename).json")
        }
        print()

        guard let choice = TerminalUtils.menu(
            "How would you like to handle existing sidecars?",
            options: [
                "Reuse all (keep existing ground truth)",
                "Regenerate all (overwrite with fresh results)",
                "Decide per-document",
                "Cancel benchmarking",
            ]
        ) else {
            throw ExitCode.success
        }

        var skipPaths: Set<String> = []

        switch choice {
        case 0: // Reuse all
            skipPaths = Set(existingPaths)
        case 1: // Regenerate all
            break
        case 2: // Per-document
            skipPaths = try promptPerDocument(existingPaths)
        default: // Cancel
            throw ExitCode.success
        }

        print()
        return skipPaths
    }

    /// Prompt for each existing sidecar individually
    private func promptPerDocument(_ paths: [String]) throws -> Set<String> {
        var skipPaths: Set<String> = []
        for path in paths {
            let filename = URL(fileURLWithPath: path).lastPathComponent
            guard let docChoice = TerminalUtils.menu(
                "\(filename).json exists. What to do?",
                options: [
                    "Reuse existing",
                    "Regenerate",
                    "Cancel benchmarking",
                ]
            ) else {
                throw ExitCode.success
            }
            switch docChoice {
            case 0: skipPaths.insert(path)
            case 2: throw ExitCode.success
            default: break
            }
        }
        return skipPaths
    }

    /// Phase A.1: Verification pause — let user review sidecar files
    func runPhaseA1(positiveDir: String, negativeDir: String?) throws {
        printBenchmarkPhaseHeader("A.1", title: "Ground Truth Verification")

        print("JSON sidecar files have been generated next to each PDF.")
        print("Please review and correct them before continuing.")
        print()
        print("Sidecar locations:")

        let fileManager = FileManager.default
        let posContents = try fileManager.contentsOfDirectory(atPath: positiveDir)
        for file in posContents.sorted() where file.hasSuffix(".pdf.json") {
            let path = (positiveDir as NSString).appendingPathComponent(file)
            print("  \(path)")
        }

        if let negDir = negativeDir {
            let negContents = try fileManager.contentsOfDirectory(atPath: negDir)
            for file in negContents.sorted() where file.hasSuffix(".pdf.json") {
                let path = (negDir as NSString).appendingPathComponent(file)
                print("  \(path)")
            }
        }

        print()

        // Offer to open sidecar files
        if TerminalUtils.confirm("Open sidecar files in default editor?") {
            for file in posContents.sorted() where file.hasSuffix(".pdf.json") {
                let path = (positiveDir as NSString).appendingPathComponent(file)
                NSWorkspace.shared.open(URL(fileURLWithPath: path))
            }
            if let negDir = negativeDir {
                let negFiles = try fileManager.contentsOfDirectory(atPath: negDir)
                for file in negFiles.sorted() where file.hasSuffix(".pdf.json") {
                    let path = (negDir as NSString).appendingPathComponent(file)
                    NSWorkspace.shared.open(URL(fileURLWithPath: path))
                }
            }
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
