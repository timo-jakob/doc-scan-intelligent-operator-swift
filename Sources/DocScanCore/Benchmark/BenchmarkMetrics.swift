import Foundation

/// Result for a single document in a benchmark run
public struct DocumentResult: Equatable {
    /// Filename of the document
    public let filename: String

    /// Whether this document is a positive sample (should match the document type)
    public let isPositiveSample: Bool

    /// Whether the model predicted this as a match
    public let predictedIsMatch: Bool

    /// Document score: 0 (fully wrong), 1 (categorization correct, extraction wrong), 2 (fully correct)
    public let documentScore: Int

    /// Whether categorization was correct
    public var categorizationCorrect: Bool {
        isPositiveSample == predictedIsMatch
    }

    /// Whether categorization AND extraction are both fully correct (score == 2)
    public var isFullyCorrect: Bool {
        documentScore == 2
    }

    public init(
        filename: String,
        isPositiveSample: Bool,
        predictedIsMatch: Bool,
        documentScore: Int
    ) {
        self.filename = filename
        self.isPositiveSample = isPositiveSample
        self.predictedIsMatch = predictedIsMatch
        self.documentScore = documentScore
    }
}

/// Computed metrics for a benchmark run
public struct BenchmarkMetrics: Equatable {
    /// Normalized score: totalScore / (2 * documentCount), range [0.0, 1.0]
    public let score: Double

    /// Sum of all document scores
    public let totalScore: Int

    /// Number of documents evaluated
    public let documentCount: Int

    /// Maximum possible score (2 * documentCount)
    public let maxScore: Int

    /// Whether the corpus included negative samples
    public let hasNegativeSamples: Bool

    /// Number of documents scoring 2 (fully correct)
    public let fullyCorrectCount: Int

    /// Number of documents scoring 1 (categorization correct, extraction wrong)
    public let partiallyCorrectCount: Int

    /// Number of documents scoring 0 (fully wrong)
    public let fullyWrongCount: Int

    /// Compute metrics from document results
    public static func compute(from results: [DocumentResult]) -> BenchmarkMetrics {
        guard !results.isEmpty else {
            return .empty
        }

        let totalScore = results.reduce(0) { $0 + $1.documentScore }
        let maxScore = 2 * results.count
        let score = Double(totalScore) / Double(maxScore)

        return BenchmarkMetrics(
            score: score,
            totalScore: totalScore,
            documentCount: results.count,
            maxScore: maxScore,
            hasNegativeSamples: results.contains { !$0.isPositiveSample },
            fullyCorrectCount: results.count(where: { $0.documentScore == 2 }),
            partiallyCorrectCount: results.count(where: { $0.documentScore == 1 }),
            fullyWrongCount: results.count(where: { $0.documentScore == 0 })
        )
    }

    /// Empty metrics for zero-document case
    static let empty = BenchmarkMetrics(
        score: 0,
        totalScore: 0,
        documentCount: 0,
        maxScore: 0,
        hasNegativeSamples: false,
        fullyCorrectCount: 0,
        partiallyCorrectCount: 0,
        fullyWrongCount: 0
    )
}

/// Result for a single model pair benchmark
public struct ModelPairResult: Equatable {
    /// VLM model name
    public let vlmModelName: String

    /// Text LLM model name
    public let textModelName: String

    /// Computed metrics
    public let metrics: BenchmarkMetrics

    /// Per-document results
    public let documentResults: [DocumentResult]

    /// Whether this pair was disqualified (e.g., timeout, crash)
    public let isDisqualified: Bool

    /// Reason for disqualification
    public let disqualificationReason: String?

    public init(
        vlmModelName: String,
        textModelName: String,
        metrics: BenchmarkMetrics,
        documentResults: [DocumentResult],
        isDisqualified: Bool = false,
        disqualificationReason: String? = nil
    ) {
        self.vlmModelName = vlmModelName
        self.textModelName = textModelName
        self.metrics = metrics
        self.documentResults = documentResults
        self.isDisqualified = isDisqualified
        self.disqualificationReason = disqualificationReason
    }
}
