import ArgumentParser
import DocScanCore
import Foundation

/// Shared helpers for CLI commands to avoid duplication between ScanCommand and BenchmarkCommand.
enum CLIHelpers {
    /// Parse a document type from a raw string value, printing errors and throwing on failure.
    static func parseDocumentType(_ rawValue: String) throws -> DocumentType {
        guard let documentType = DocumentType(rawValue: rawValue.lowercased()) else {
            let validTypes = DocumentType.allCases.map(\.rawValue).joined(separator: ", ")
            print("Invalid document type: '\(rawValue)'")
            print("Valid types: \(validTypes)")
            throw ExitCode.failure
        }
        return documentType
    }

    /// Load configuration from an optional path, falling back to the default config location
    /// and finally to the built-in defaults.
    static func loadConfiguration(configPath: String?) throws -> Configuration {
        if let configPath {
            return try Configuration.load(from: configPath)
        }
        let defaultPath = Configuration.defaultConfigPath
        if FileManager.default.fileExists(atPath: defaultPath) {
            return try Configuration.load(from: defaultPath)
        }
        return Configuration.defaultConfiguration
    }
}
