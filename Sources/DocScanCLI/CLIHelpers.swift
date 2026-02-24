import ArgumentParser
import DocScanCore
import Foundation

// MARK: - DocumentType ArgumentParser Integration

/// Enables `--type invoice` / `--type prescription` directly in ArgumentParser options.
extension DocumentType: ExpressibleByArgument {}

/// Shared helpers for CLI commands to avoid duplication between ScanCommand and BenchmarkCommand.
enum CLIHelpers {
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
