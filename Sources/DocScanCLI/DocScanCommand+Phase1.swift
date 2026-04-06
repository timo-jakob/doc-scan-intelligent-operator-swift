import ArgumentParser
import DocScanCore
import Foundation

// MARK: - Phase 1: Verbose Output

extension ScanCommand {
    func printPhaseHeader(number: Int, title: String) {
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("Phase \(number): \(title)")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print()
    }

    func displayCategorizationResults(
        _ categorization: CategorizationVerification,
        documentType: DocumentType,
    ) {
        print("╔══════════════════════════════════════════════════╗")
        print("║         Categorization Results                   ║")
        print("╠══════════════════════════════════════════════════╣")
        let vlmLine = "║ \(categorization.vlmResult.displayLabel):"
        print(vlmLine.padding(toLength: 51, withPad: " ", startingAt: 0) + "║")
        displayCategorizationResult(
            categorization.vlmResult, prefix: "║   ", documentType: documentType,
        )
        print("║                                                  ║")
        let ocrLine = "║ \(categorization.ocrResult.displayLabel):"
        print(ocrLine.padding(toLength: 51, withPad: " ", startingAt: 0) + "║")
        displayCategorizationResult(
            categorization.ocrResult, prefix: "║   ", documentType: documentType,
        )
        print("╚══════════════════════════════════════════════════╝")
        print()
    }

    private func displayCategorizationResult(
        _ result: CategorizationResult,
        prefix: String,
        documentType: DocumentType,
    ) {
        let typeName = documentType.displayName
        let matchStatus = result.isMatch ? "✅ \(typeName)" : "❌ Not \(typeName)"
        print("\(prefix)\(matchStatus) (confidence: \(result.confidence.rawValue))")
        if let reason = result.reason, verbose {
            print("\(prefix)Reason: \(String(reason.prefix(40)))")
        }
    }

    func determineIsMatchVerbose(
        _ categorization: CategorizationVerification,
        documentType: DocumentType,
    ) throws -> Bool {
        let vlmTimedOut = categorization.vlmResult.isTimedOut
        let ocrTimedOut = categorization.ocrResult.isTimedOut
        let typeName = documentType.displayName.lowercased()

        if vlmTimedOut, ocrTimedOut {
            print("❌ Both methods timed out")
            throw ExitCode.failure
        }
        if vlmTimedOut {
            print("⏱️  VLM timed out - using OCR result")
            return categorization.ocrResult.isMatch
        }
        if ocrTimedOut {
            print("⏱️  OCR timed out - using VLM result")
            return categorization.vlmResult.isMatch
        }
        if categorization.bothAgree {
            let isMatch = categorization.agreedIsMatch ?? false
            let vlmLabel = categorization.vlmResult.shortDisplayLabel
            let textLabel = categorization.ocrResult.shortDisplayLabel
            let verb = isMatch ? "IS" : "is NOT"
            print("✅ \(vlmLabel) and \(textLabel) agree: This \(verb) a \(typeName)")
            return isMatch
        }
        return try resolveCategorizationVerbose(
            categorization, documentType: documentType,
        )
    }

    private func resolveCategorizationVerbose(
        _ categorization: CategorizationVerification,
        documentType: DocumentType,
    ) throws -> Bool {
        let vlmLabel = categorization.vlmResult.shortDisplayLabel
        let textLabel = categorization.ocrResult.shortDisplayLabel
        let typeName = documentType.displayName

        print("⚠️  CATEGORIZATION CONFLICT")
        print()
        let vlmSays = categorization.vlmResult.isMatch ? typeName : "Not a \(typeName.lowercased())"
        let ocrSays = categorization.ocrResult.isMatch ? typeName : "Not a \(typeName.lowercased())"
        print("  \(vlmLabel) says: \(vlmSays)")
        print("  \(textLabel) says: \(ocrSays)")
        print()

        if let autoResolveMode = autoResolve {
            return try applyAutoResolveVerbose(
                autoResolveMode,
                categorization: categorization,
                documentType: documentType,
            )
        }
        return try interactiveResolveVerbose(
            categorization, documentType: documentType,
        )
    }

    private func applyAutoResolveVerbose(
        _ mode: String,
        categorization: CategorizationVerification,
        documentType: DocumentType,
    ) throws -> Bool {
        let normalizedMode = mode.lowercased()
        guard ["vlm", "ocr"].contains(normalizedMode) else {
            print("❌ Invalid --auto-resolve option: '\(mode)'")
            print("   Valid options: vlm, ocr")
            throw ExitCode.failure
        }
        let useVLM = normalizedMode == "vlm"
        let chosen = useVLM ? categorization.vlmResult : categorization.ocrResult
        let result = chosen.isMatch
        let typeName = documentType.displayName.lowercased()
        let desc = result ? typeName : "Not a \(typeName)"
        print("🤖 Auto-resolve: Using \(chosen.shortDisplayLabel) → \(desc)")
        return result
    }

    private func interactiveResolveVerbose(
        _ categorization: CategorizationVerification,
        documentType: DocumentType,
    ) throws -> Bool {
        let vlmLabel = categorization.vlmResult.shortDisplayLabel
        let textLabel = categorization.ocrResult.shortDisplayLabel
        let typeName = documentType.displayName
        let notType = "Not a \(typeName.lowercased())"

        print("Which result do you trust?")
        print("  [1] \(vlmLabel): \(categorization.vlmResult.isMatch ? typeName : notType)")
        print("  [2] \(textLabel): \(categorization.ocrResult.isMatch ? typeName : notType)")

        while true {
            print("Enter your choice (1 or 2): ", terminator: "")
            guard let input = readLine()?.trimmingCharacters(in: .whitespaces) else {
                throw ExitCode.failure
            }
            if input == "1" { return categorization.vlmResult.isMatch }
            if input == "2" { return categorization.ocrResult.isMatch }
            print("Invalid choice. Please enter 1 or 2.")
        }
    }
}

// MARK: - Phase 1: Compact Output

extension ScanCommand {
    func determineIsMatchCompact(
        _ categorization: CategorizationVerification,
        documentType: DocumentType,
    ) throws -> Bool {
        let vlmTimedOut = categorization.vlmResult.isTimedOut
        let ocrTimedOut = categorization.ocrResult.isTimedOut
        let vlmConf = categorization.vlmResult.confidence
        let ocrConf = categorization.ocrResult.confidence
        let typeName = documentType.displayName.lowercased()

        if vlmTimedOut, ocrTimedOut {
            writeStdout("📋 Phase 1  ❌ both methods timed out\n")
            throw ExitCode.failure
        }

        if vlmTimedOut {
            let isMatch = categorization.ocrResult.isMatch
            let label = isMatch ? "✅ \(typeName)" : "❌ unknown document"
            writeStdout("📋 Phase 1  \(label)  ⏱️ VLM · OCR: \(ocrConf.rawValue)\n")
            return isMatch
        }

        if ocrTimedOut {
            let isMatch = categorization.vlmResult.isMatch
            let label = isMatch ? "✅ \(typeName)" : "❌ unknown document"
            writeStdout("📋 Phase 1  \(label)  VLM: \(vlmConf.rawValue) · ⏱️ OCR\n")
            return isMatch
        }

        if categorization.bothAgree {
            let isMatch = categorization.agreedIsMatch ?? false
            let label = isMatch ? "✅ \(typeName)" : "❌ unknown document"
            writeStdout("📋 Phase 1  \(label)  VLM: \(vlmConf.rawValue) · OCR: \(ocrConf.rawValue)\n")
            return isMatch
        }

        return try resolveConflictCompact(
            categorization,
            documentType: documentType,
            vlmConf: vlmConf,
            ocrConf: ocrConf,
        )
    }

    private func resolveConflictCompact(
        _ categorization: CategorizationVerification,
        documentType: DocumentType,
        vlmConf: ConfidenceLevel,
        ocrConf: ConfidenceLevel,
    ) throws -> Bool {
        let vlmYN = categorization.vlmResult.isMatch ? "YES" : "NO"
        let ocrYN = categorization.ocrResult.isMatch ? "YES" : "NO"
        let conflictInfo = "VLM=\(vlmYN)(\(vlmConf.rawValue)) · OCR=\(ocrYN)(\(ocrConf.rawValue))"
        let prompt = "📋 Phase 1  ⚠️  conflict  \(conflictInfo)  →  [v]lm or [o]cr? "

        if let mode = autoResolve {
            let normalizedMode = mode.lowercased()
            guard ["vlm", "ocr"].contains(normalizedMode) else {
                print("❌ Invalid --auto-resolve option: '\(mode)'")
                throw ExitCode.failure
            }
            let useVLM = normalizedMode == "vlm"
            let result = useVLM ? categorization.vlmResult.isMatch : categorization.ocrResult.isMatch
            let typeName = documentType.displayName.lowercased()
            let matchStr = result ? "✅ \(typeName)" : "❌ unknown document"
            writeStdout("📋 Phase 1  ⚠️  \(matchStr)  \(conflictInfo)  [auto:\(normalizedMode)]\n")
            return result
        }

        writeStdout(prompt)
        while true {
            guard let input = readLine()?.trimmingCharacters(in: .whitespaces).lowercased() else {
                writeStdout("\n")
                throw ExitCode.failure
            }
            if input == "v" || input == "vlm" { return categorization.vlmResult.isMatch }
            if input == "o" || input == "ocr" { return categorization.ocrResult.isMatch }
            let prefix = isInteractiveTerminal ? "\r" : ""
            writeStdout("\(prefix)\(prompt)")
        }
    }
}
