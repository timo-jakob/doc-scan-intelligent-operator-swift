import Foundation
import Yams

/// Processing settings for LLM generation and PDF rendering
public struct ProcessingSettings: Codable, Equatable, Sendable {
    /// Maximum number of tokens to generate
    public var maxTokens: Int

    /// Temperature for text generation
    public var temperature: Double

    /// DPI for PDF to image conversion
    public var pdfDPI: Int

    public init(
        maxTokens: Int = Configuration.defaultMaxTokens,
        temperature: Double = Configuration.defaultTemperature,
        pdfDPI: Int = Configuration.defaultPdfDPI
    ) {
        self.maxTokens = maxTokens
        self.temperature = temperature
        self.pdfDPI = pdfDPI
    }

    /// Validate that all processing settings are within acceptable ranges
    public func validate() throws(DocScanError) {
        guard maxTokens > 0 else {
            throw DocScanError.configurationError("maxTokens must be > 0")
        }
        guard temperature >= 0, temperature <= 2.0 else {
            throw DocScanError.configurationError("temperature must be 0..2")
        }
        guard pdfDPI > 0 else {
            throw DocScanError.configurationError("pdfDPI must be > 0")
        }
    }
}

/// Output formatting settings for invoice filenames
public struct OutputSettings: Codable, Equatable, Sendable {
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

/// Benchmark-related settings for model evaluation
///
/// - Note: This struct's synthesized `Codable` uses its own property names as keys
///   (`textLLMModels`). When serialized as part of `Configuration`,
///   the parent's custom `encode(to:)`/`init(from:)` maps these to the flat YAML
///   key `benchmarkTextLLMModels` for backward compatibility.
///   VLM models are discovered dynamically via `--family` (see `HuggingFaceClient`).
///   Legacy `benchmarkVLMModels` keys in existing YAML files are silently ignored.
public struct BenchmarkSettings: Codable, Equatable, Sendable {
    /// Hugging Face username (for model discovery)
    public var huggingFaceUsername: String?

    /// Override TextLLM model list for benchmarking (nil = use DefaultModelLists.textLLMModels)
    public var textLLMModels: [String]?

    public init(
        huggingFaceUsername: String? = nil,
        textLLMModels: [String]? = nil
    ) {
        self.huggingFaceUsername = huggingFaceUsername
        self.textLLMModels = textLLMModels
    }
}

/// Configuration for document scanning and invoice processing
public struct Configuration: Codable, Equatable, Sendable {
    /// VLM model identifier (e.g., "mlx-community/Qwen2-VL-7B-Instruct-4bit")
    public var modelName: String

    /// Text LLM model identifier (e.g., "mlx-community/Qwen2.5-7B-Instruct-4bit")
    public var textModelName: String

    /// Directory to cache downloaded models
    public var modelCacheDir: String

    /// Processing settings (generation parameters and PDF rendering)
    public var processing: ProcessingSettings

    /// Whether to enable verbose logging
    public var verbose: Bool

    /// Output formatting settings
    public var output: OutputSettings

    /// Benchmark-related settings
    public var benchmark: BenchmarkSettings

    /// Maximum number of tokens to generate (convenience accessor)
    public var maxTokens: Int {
        get { processing.maxTokens }
        set { processing.maxTokens = newValue }
    }

    /// Temperature for text generation (convenience accessor)
    public var temperature: Double {
        get { processing.temperature }
        set { processing.temperature = newValue }
    }

    /// DPI for PDF to image conversion (convenience accessor)
    public var pdfDPI: Int {
        get { processing.pdfDPI }
        set { processing.pdfDPI = newValue }
    }

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

    // MARK: - Default Values

    public static let defaultModelName = "mlx-community/Qwen2-VL-7B-Instruct-4bit"
    public static let defaultTextModelName = "mlx-community/Qwen2.5-7B-Instruct-4bit"
    public static let defaultMaxTokens = 256
    public static let defaultTemperature = 0.1
    public static let defaultPdfDPI = 150

    private static var defaultCacheDir: String {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".cache/docscan/models")
            .path
    }

    public static var defaultConfigDir: String {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".docscan").path
    }

    public static var defaultConfigPath: String {
        (defaultConfigDir as NSString).appendingPathComponent("docscan-config.yaml")
    }

    public init(
        modelName: String = Configuration.defaultModelName,
        textModelName: String = Configuration.defaultTextModelName,
        modelCacheDir: String? = nil,
        processing: ProcessingSettings = ProcessingSettings(),
        verbose: Bool = false,
        output: OutputSettings = OutputSettings(),
        benchmark: BenchmarkSettings = BenchmarkSettings()
    ) {
        self.modelName = modelName
        self.textModelName = textModelName
        self.modelCacheDir = modelCacheDir ?? Self.defaultCacheDir
        self.processing = processing
        self.verbose = verbose
        self.output = output
        self.benchmark = benchmark
    }

    /// Explicit CodingKeys to maintain flat YAML format
    enum CodingKeys: String, CodingKey {
        case modelName, textModelName, modelCacheDir
        case maxTokens, temperature, pdfDPI
        case verbose, output, huggingFaceUsername
        case benchmarkTextLLMModels
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        modelName = try container.decodeIfPresent(String.self, forKey: .modelName)
            ?? Self.defaultModelName
        textModelName = try container.decodeIfPresent(String.self, forKey: .textModelName)
            ?? Self.defaultTextModelName
        modelCacheDir = try container.decodeIfPresent(String.self, forKey: .modelCacheDir)
            ?? Self.defaultCacheDir
        processing = try ProcessingSettings(
            maxTokens: container.decodeIfPresent(Int.self, forKey: .maxTokens)
                ?? Self.defaultMaxTokens,
            temperature: container.decodeIfPresent(Double.self, forKey: .temperature)
                ?? Self.defaultTemperature,
            pdfDPI: container.decodeIfPresent(Int.self, forKey: .pdfDPI)
                ?? Self.defaultPdfDPI
        )
        verbose = try container.decodeIfPresent(Bool.self, forKey: .verbose) ?? false
        output = try container.decodeIfPresent(OutputSettings.self, forKey: .output) ?? OutputSettings()
        let hfUsername = try container.decodeIfPresent(String.self, forKey: .huggingFaceUsername)
        let textLLMModels = try container.decodeIfPresent([String].self, forKey: .benchmarkTextLLMModels)
        benchmark = BenchmarkSettings(
            huggingFaceUsername: hfUsername,
            textLLMModels: textLLMModels
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(modelName, forKey: .modelName)
        try container.encode(textModelName, forKey: .textModelName)
        try container.encode(modelCacheDir, forKey: .modelCacheDir)
        try container.encode(processing.maxTokens, forKey: .maxTokens)
        try container.encode(processing.temperature, forKey: .temperature)
        try container.encode(processing.pdfDPI, forKey: .pdfDPI)
        try container.encode(verbose, forKey: .verbose)
        try container.encode(output, forKey: .output)
        try container.encodeIfPresent(benchmark.huggingFaceUsername, forKey: .huggingFaceUsername)
        try container.encodeIfPresent(benchmark.textLLMModels, forKey: .benchmarkTextLLMModels)
    }

    /// Load configuration from YAML file
    public static func load(from path: String) throws -> Configuration {
        let url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: path) else {
            throw DocScanError.fileNotFound(path)
        }

        let data = try Data(contentsOf: url)
        let decoder = YAMLDecoder()
        let config = try decoder.decode(Configuration.self, from: data)
        try config.processing.validate()
        return config
    }

    /// Save configuration to YAML file
    public func save(to path: String) throws {
        let url = URL(fileURLWithPath: path)
        let dir = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let encoder = YAMLEncoder()
        let yaml = try encoder.encode(self)
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
        if let hfUser = benchmark.huggingFaceUsername {
            desc += "\n  HuggingFace User: \(hfUser)"
        }
        return desc
    }
}
