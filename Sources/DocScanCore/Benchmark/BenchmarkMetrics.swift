import Foundation

// MARK: - Shared Protocol

/// Common properties for benchmark results, used for generic sorting and display
public protocol BenchmarkResultProtocol: Sendable {
    var modelName: String { get }
    var totalScore: Int { get }
    var maxScore: Int { get }
    var score: Double { get }
    var elapsedSeconds: TimeInterval { get }
    var isDisqualified: Bool { get }
    var disqualificationReason: String? { get }
}

public extension Sequence where Element: BenchmarkResultProtocol {
    /// Return qualifying (non-disqualified) results ranked by score descending, then elapsed time ascending.
    /// Uses cross-multiplication for score comparison to avoid floating-point imprecision.
    func rankedByScore() -> [Element] {
        filter { !$0.isDisqualified }
            .sorted { lhs, rhs in
                // Cross-multiply to compare totalScore/maxScore without floating point:
                // lhs.score > rhs.score  ⟺  lhs.totalScore * rhs.maxScore > rhs.totalScore * lhs.maxScore
                let lhsCross = lhs.totalScore * rhs.maxScore
                let rhsCross = rhs.totalScore * lhs.maxScore
                if lhsCross != rhsCross { return lhsCross > rhsCross }
                return lhs.elapsedSeconds < rhs.elapsedSeconds
            }
    }
}

// MARK: - VLM Benchmark Results

/// Result for a single document in a VLM categorization benchmark
public struct VLMDocumentResult: Codable, Equatable, Sendable {
    /// Filename of the document
    public let filename: String

    /// Whether this document is a positive sample (should match the document type)
    public let isPositiveSample: Bool

    /// Whether the model predicted this as a match
    public let predictedIsMatch: Bool

    /// Whether the prediction was correct (TP or TN)
    public var correct: Bool {
        isPositiveSample == predictedIsMatch
    }

    /// Score: 1 if correct, 0 if wrong
    public var score: Int {
        correct ? 1 : 0
    }

    public init(
        filename: String,
        isPositiveSample: Bool,
        predictedIsMatch: Bool
    ) {
        self.filename = filename
        self.isPositiveSample = isPositiveSample
        self.predictedIsMatch = predictedIsMatch
    }
}

/// Aggregated result for a single VLM model benchmark
public struct VLMBenchmarkResult: Codable, Equatable, Sendable, BenchmarkResultProtocol {
    /// Model name
    public let modelName: String

    /// Sum of all document scores
    public let totalScore: Int

    /// Maximum possible score (1 * documentCount)
    public let maxScore: Int

    /// Normalized score: totalScore / maxScore, range [0.0, 1.0]
    public var score: Double {
        maxScore > 0 ? Double(totalScore) / Double(maxScore) : 0
    }

    /// Per-document results
    public let documentResults: [VLMDocumentResult]

    /// Total elapsed time in seconds for this model's full benchmark
    public let elapsedSeconds: TimeInterval

    /// Whether this model was disqualified
    public let isDisqualified: Bool

    /// Reason for disqualification
    public let disqualificationReason: String?

    /// Number of true positives
    public var truePositives: Int {
        documentResults.count(where: { $0.isPositiveSample && $0.predictedIsMatch })
    }

    /// Number of true negatives
    public var trueNegatives: Int {
        documentResults.count(where: { !$0.isPositiveSample && !$0.predictedIsMatch })
    }

    /// Number of false positives
    public var falsePositives: Int {
        documentResults.count(where: { !$0.isPositiveSample && $0.predictedIsMatch })
    }

    /// Number of false negatives
    public var falseNegatives: Int {
        documentResults.count(where: { $0.isPositiveSample && !$0.predictedIsMatch })
    }

    public init(
        modelName: String,
        totalScore: Int,
        maxScore: Int,
        documentResults: [VLMDocumentResult],
        elapsedSeconds: TimeInterval,
        isDisqualified: Bool = false,
        disqualificationReason: String? = nil
    ) {
        self.modelName = modelName
        self.totalScore = totalScore
        self.maxScore = maxScore
        self.documentResults = documentResults
        self.elapsedSeconds = elapsedSeconds
        self.isDisqualified = isDisqualified
        self.disqualificationReason = disqualificationReason
    }

    /// Create from document results
    public static func from(
        modelName: String,
        documentResults: [VLMDocumentResult],
        elapsedSeconds: TimeInterval
    ) -> VLMBenchmarkResult {
        let totalScore = documentResults.reduce(0) { $0 + $1.score }
        return VLMBenchmarkResult(
            modelName: modelName,
            totalScore: totalScore,
            maxScore: documentResults.count,
            documentResults: documentResults,
            elapsedSeconds: elapsedSeconds
        )
    }

    /// Create a disqualified result
    public static func disqualified(
        modelName: String,
        reason: String
    ) -> VLMBenchmarkResult {
        VLMBenchmarkResult(
            modelName: modelName,
            totalScore: 0,
            maxScore: 0,
            documentResults: [],
            elapsedSeconds: 0,
            isDisqualified: true,
            disqualificationReason: reason
        )
    }
}

// MARK: - TextLLM Benchmark Results

/// Result for a single document in a TextLLM benchmark
public struct TextLLMDocumentResult: Codable, Equatable, Sendable {
    /// Filename of the document
    public let filename: String

    /// Whether this document is a positive sample (should match the document type)
    public let isPositiveSample: Bool

    /// Whether categorization was correct
    public let categorizationCorrect: Bool

    /// Whether extraction was correct (only relevant for positive samples)
    public let extractionCorrect: Bool

    /// Score: 0 (both wrong), 1 (one correct), or 2 (both correct)
    public var score: Int {
        (categorizationCorrect ? 1 : 0) + (extractionCorrect ? 1 : 0)
    }

    public init(
        filename: String,
        isPositiveSample: Bool,
        categorizationCorrect: Bool,
        extractionCorrect: Bool
    ) {
        self.filename = filename
        self.isPositiveSample = isPositiveSample
        self.categorizationCorrect = categorizationCorrect
        self.extractionCorrect = extractionCorrect
    }
}

/// Aggregated result for a single TextLLM model benchmark
public struct TextLLMBenchmarkResult: Codable, Equatable, Sendable, BenchmarkResultProtocol {
    /// Model name
    public let modelName: String

    /// Sum of all document scores
    public let totalScore: Int

    /// Maximum possible score (2 * documentCount)
    public let maxScore: Int

    /// Normalized score: totalScore / maxScore, range [0.0, 1.0]
    public var score: Double {
        maxScore > 0 ? Double(totalScore) / Double(maxScore) : 0
    }

    /// Per-document results
    public let documentResults: [TextLLMDocumentResult]

    /// Total elapsed time in seconds for this model's full benchmark
    public let elapsedSeconds: TimeInterval

    /// Whether this model was disqualified
    public let isDisqualified: Bool

    /// Reason for disqualification
    public let disqualificationReason: String?

    /// Number of documents scoring 2 (fully correct)
    public var fullyCorrectCount: Int {
        documentResults.count(where: { $0.score == 2 })
    }

    /// Number of documents scoring 1 (partially correct)
    public var partiallyCorrectCount: Int {
        documentResults.count(where: { $0.score == 1 })
    }

    /// Number of documents scoring 0 (fully wrong)
    public var fullyWrongCount: Int {
        documentResults.count(where: { $0.score == 0 })
    }

    public init(
        modelName: String,
        totalScore: Int,
        maxScore: Int,
        documentResults: [TextLLMDocumentResult],
        elapsedSeconds: TimeInterval,
        isDisqualified: Bool = false,
        disqualificationReason: String? = nil
    ) {
        self.modelName = modelName
        self.totalScore = totalScore
        self.maxScore = maxScore
        self.documentResults = documentResults
        self.elapsedSeconds = elapsedSeconds
        self.isDisqualified = isDisqualified
        self.disqualificationReason = disqualificationReason
    }

    /// Create from document results
    public static func from(
        modelName: String,
        documentResults: [TextLLMDocumentResult],
        elapsedSeconds: TimeInterval
    ) -> TextLLMBenchmarkResult {
        let totalScore = documentResults.reduce(0) { $0 + $1.score }
        return TextLLMBenchmarkResult(
            modelName: modelName,
            totalScore: totalScore,
            maxScore: 2 * documentResults.count,
            documentResults: documentResults,
            elapsedSeconds: elapsedSeconds
        )
    }

    /// Create a disqualified result
    public static func disqualified(
        modelName: String,
        reason: String
    ) -> TextLLMBenchmarkResult {
        TextLLMBenchmarkResult(
            modelName: modelName,
            totalScore: 0,
            maxScore: 0,
            documentResults: [],
            elapsedSeconds: 0,
            isDisqualified: true,
            disqualificationReason: reason
        )
    }
}
