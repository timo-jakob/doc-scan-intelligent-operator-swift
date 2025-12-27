import Foundation
import Yams

/// Output formatting settings for invoice filenames
public struct OutputSettings: Codable, Equatable {
    /// Date format for invoice filename (e.g., "yyyy-MM-dd")
    public var dateFormat: String

    /// Filename pattern (e.g., "{date}_Rechnung_{company}.pdf")
    public var filenamePattern: String

    public init(
        dateFormat: String = "yyyy-MM-dd",
        filenamePattern: String = "{date}_Rechnung_{company}.pdf"
    ) {
        self.dateFormat = dateFormat
        self.filenamePattern = filenamePattern
    }
}

/// Configuration for document scanning and invoice processing
public struct Configuration: Codable {
    /// Model identifier (e.g., "mlx-community/Qwen2-VL-2B-Instruct-4bit")
    public var modelName: String

    /// Directory to cache downloaded models
    public var modelCacheDir: String

    /// Maximum number of tokens to generate
    public var maxTokens: Int

    /// Temperature for text generation
    public var temperature: Double

    /// DPI for PDF to image conversion
    public var pdfDPI: Int

    /// Whether to enable verbose logging
    public var verbose: Bool

    /// Output formatting settings
    public var output: OutputSettings

    /// Date format for invoice filename (convenience accessor)
    public var dateFormat: String {
        get { output.dateFormat }
        set { output.dateFormat = newValue }
    }

    /// Filename pattern (convenience accessor)
    public var filenamePattern: String {
        get { output.filenamePattern }
        set { output.filenamePattern = newValue }
    }

    public init(
        modelName: String = "mlx-community/Qwen2-VL-2B-Instruct-4bit",
        modelCacheDir: String? = nil,
        maxTokens: Int = 256,
        temperature: Double = 0.1,
        pdfDPI: Int = 150,
        verbose: Bool = false,
        output: OutputSettings = OutputSettings()
    ) {
        self.modelName = modelName
        self.modelCacheDir = modelCacheDir ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".cache/docscan/models")
            .path
        self.maxTokens = maxTokens
        self.temperature = temperature
        self.pdfDPI = pdfDPI
        self.verbose = verbose
        self.output = output
    }

    /// Load configuration from YAML file
    public static func load(from path: String) throws -> Configuration {
        let url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: path) else {
            throw DocScanError.fileNotFound(path)
        }

        let data = try Data(contentsOf: url)
        let decoder = YAMLDecoder()
        return try decoder.decode(Configuration.self, from: data)
    }

    /// Save configuration to YAML file
    public func save(to path: String) throws {
        let encoder = YAMLEncoder()
        let yaml = try encoder.encode(self)
        let url = URL(fileURLWithPath: path)
        try yaml.write(to: url, atomically: true, encoding: .utf8)
    }

    /// Get default configuration
    public static var defaultConfiguration: Configuration {
        Configuration()
    }
}

// MARK: - CustomStringConvertible
extension Configuration: CustomStringConvertible {
    public var description: String {
        """
        Configuration:
          Model: \(modelName)
          Cache: \(modelCacheDir)
          Max Tokens: \(maxTokens)
          Temperature: \(temperature)
          PDF DPI: \(pdfDPI)
          Verbose: \(verbose)
          Date Format: \(dateFormat)
          Filename Pattern: \(filenamePattern)
        """
    }
}
