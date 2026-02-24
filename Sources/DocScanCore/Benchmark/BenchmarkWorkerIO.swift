import Foundation

/// Which benchmark phase the worker should execute
public enum BenchmarkWorkerPhase: String, Codable, Sendable {
    /// Vision-Language Model categorization benchmark
    case vlm
    /// Text LLM extraction and categorization benchmark
    case textLLM
}

/// Positive and negative PDF paths for a benchmark run
public struct BenchmarkPDFSet: Codable, Equatable, Sendable {
    /// Absolute paths to positive PDF files
    public let positivePDFs: [String]

    /// Absolute paths to negative PDF files
    public let negativePDFs: [String]

    /// Total number of documents in this set
    public var count: Int {
        positivePDFs.count + negativePDFs.count
    }

    public init(positivePDFs: [String], negativePDFs: [String]) {
        self.positivePDFs = positivePDFs
        self.negativePDFs = negativePDFs
    }
}

/// Pre-extracted data needed for the TextLLM benchmark phase
public struct TextLLMInputData: Codable, Equatable, Sendable {
    /// OCR texts keyed by PDF path
    public let ocrTexts: [String: String]

    /// Ground truths keyed by PDF path
    public let groundTruths: [String: GroundTruth]

    public init(ocrTexts: [String: String], groundTruths: [String: GroundTruth]) {
        self.ocrTexts = ocrTexts
        self.groundTruths = groundTruths
    }
}

/// Input parameters serialized to a temp file for the benchmark worker subprocess
public struct BenchmarkWorkerInput: Codable, Sendable {
    /// Which phase to run
    public let phase: BenchmarkWorkerPhase

    /// Model name to benchmark (e.g., "mlx-community/Qwen2-VL-2B-Instruct-4bit")
    public let modelName: String

    /// Positive and negative PDF paths
    public let pdfSet: BenchmarkPDFSet

    /// Per-inference timeout in seconds
    public let timeoutSeconds: TimeInterval

    /// Document type being benchmarked
    public let documentType: DocumentType

    /// Full configuration (includes verbose flag for worker logging)
    public let configuration: Configuration

    /// Pre-extracted data for the TextLLM phase (nil for VLM phase)
    public let textLLMData: TextLLMInputData?

    public init(
        phase: BenchmarkWorkerPhase,
        modelName: String,
        pdfSet: BenchmarkPDFSet,
        timeoutSeconds: TimeInterval,
        documentType: DocumentType,
        configuration: Configuration,
        textLLMData: TextLLMInputData? = nil
    ) {
        self.phase = phase
        self.modelName = modelName
        self.pdfSet = pdfSet
        self.timeoutSeconds = timeoutSeconds
        self.documentType = documentType
        self.configuration = configuration
        self.textLLMData = textLLMData
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
