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
    /// VLM model identifier (e.g., "mlx-community/Qwen2-VL-2B-Instruct-4bit")
    public var modelName: String

    /// Text LLM model identifier (e.g., "mlx-community/Qwen2.5-7B-Instruct-4bit")
    public var textModelName: String

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

    /// Hugging Face username (for model discovery)
    public var huggingFaceUsername: String?

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

    /// Default text model name
    public static let defaultTextModelName = "mlx-community/Qwen2.5-7B-Instruct-4bit"

    /// Default cache directory path
    private static var defaultCacheDir: String {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".cache/docscan/models")
            .path
    }

    public init(
        modelName: String = "mlx-community/Qwen2-VL-2B-Instruct-4bit",
        textModelName: String = Configuration.defaultTextModelName,
        modelCacheDir: String? = nil,
        maxTokens: Int = 256,
        temperature: Double = 0.1,
        pdfDPI: Int = 150,
        verbose: Bool = false,
        output: OutputSettings = OutputSettings(),
        huggingFaceUsername: String? = nil
    ) {
        self.modelName = modelName
        self.textModelName = textModelName
        self.modelCacheDir = modelCacheDir ?? Self.defaultCacheDir
        self.maxTokens = maxTokens
        self.temperature = temperature
        self.pdfDPI = pdfDPI
        self.verbose = verbose
        self.output = output
        self.huggingFaceUsername = huggingFaceUsername
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        modelName = try container.decodeIfPresent(String.self, forKey: .modelName)
            ?? "mlx-community/Qwen2-VL-2B-Instruct-4bit"
        textModelName = try container.decodeIfPresent(String.self, forKey: .textModelName)
            ?? Configuration.defaultTextModelName
        modelCacheDir = try container.decodeIfPresent(String.self, forKey: .modelCacheDir)
            ?? Self.defaultCacheDir
        maxTokens = try container.decodeIfPresent(Int.self, forKey: .maxTokens) ?? 256
        temperature = try container.decodeIfPresent(Double.self, forKey: .temperature) ?? 0.1
        pdfDPI = try container.decodeIfPresent(Int.self, forKey: .pdfDPI) ?? 150
        verbose = try container.decodeIfPresent(Bool.self, forKey: .verbose) ?? false
        output = try container.decodeIfPresent(OutputSettings.self, forKey: .output) ?? OutputSettings()
        huggingFaceUsername = try container.decodeIfPresent(String.self, forKey: .huggingFaceUsername)
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
        var desc = """
        Configuration:
          VLM Model: \(modelName)
          Text Model: \(textModelName)
          Cache: \(modelCacheDir)
          Max Tokens: \(maxTokens)
          Temperature: \(temperature)
          PDF DPI: \(pdfDPI)
          Verbose: \(verbose)
          Date Format: \(dateFormat)
          Filename Pattern: \(filenamePattern)
        """
        if let hfUser = huggingFaceUsername {
            desc += "\n  HuggingFace User: \(hfUser)"
        }
        return desc
    }
}
