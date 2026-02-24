import Foundation

/// Which benchmark phase the worker should execute
public enum BenchmarkWorkerPhase: String, Codable, Sendable {
    case vlm
    case textLLM
}

/// Input parameters serialized to a temp file for the benchmark worker subprocess
public struct BenchmarkWorkerInput: Codable, Sendable {
    /// Which phase to run
    public let phase: BenchmarkWorkerPhase

    /// Model name to benchmark (e.g., "mlx-community/Qwen2-VL-2B-Instruct-4bit")
    public let modelName: String

    /// Absolute paths to positive PDF files
    public let positivePDFs: [String]

    /// Absolute paths to negative PDF files
    public let negativePDFs: [String]

    /// Per-inference timeout in seconds
    public let timeoutSeconds: TimeInterval

    /// Document type being benchmarked
    public let documentType: DocumentType

    /// Full configuration (needed for model loading, PDF settings, etc.)
    public let configuration: Configuration

    /// Whether verbose output is enabled
    public let verbose: Bool

    /// Pre-extracted OCR texts keyed by PDF path (TextLLM phase only)
    public let ocrTexts: [String: String]?

    /// Ground truths keyed by PDF path (TextLLM phase only)
    public let groundTruths: [String: GroundTruth]?

    public init(
        phase: BenchmarkWorkerPhase,
        modelName: String,
        positivePDFs: [String],
        negativePDFs: [String],
        timeoutSeconds: TimeInterval,
        documentType: DocumentType,
        configuration: Configuration,
        verbose: Bool,
        ocrTexts: [String: String]? = nil,
        groundTruths: [String: GroundTruth]? = nil
    ) {
        self.phase = phase
        self.modelName = modelName
        self.positivePDFs = positivePDFs
        self.negativePDFs = negativePDFs
        self.timeoutSeconds = timeoutSeconds
        self.documentType = documentType
        self.configuration = configuration
        self.verbose = verbose
        self.ocrTexts = ocrTexts
        self.groundTruths = groundTruths
    }

    /// Create a disqualified output for the appropriate phase when the worker encounters an error
    public func makeDisqualifiedOutput(reason: String) -> BenchmarkWorkerOutput {
        switch phase {
        case .vlm:
            .vlm(.disqualified(modelName: modelName, reason: reason))
        case .textLLM:
            .textLLM(.disqualified(modelName: modelName, reason: reason))
        }
    }
}

/// Output written by the benchmark worker subprocess.
/// Exactly one result variant is produced per worker invocation.
public enum BenchmarkWorkerOutput: Codable, Equatable, Sendable {
    case vlm(VLMBenchmarkResult)
    case textLLM(TextLLMBenchmarkResult)

    /// Extract the VLM result, or nil if this is a TextLLM output
    public var vlmResult: VLMBenchmarkResult? {
        if case let .vlm(result) = self { return result }
        return nil
    }

    /// Extract the TextLLM result, or nil if this is a VLM output
    public var textLLMResult: TextLLMBenchmarkResult? {
        if case let .textLLM(result) = self { return result }
        return nil
    }
}
