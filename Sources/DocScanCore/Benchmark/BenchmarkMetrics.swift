import Foundation

/// Result for a single document in a benchmark run
public struct DocumentResult: Equatable {
    /// Filename of the document
    public let filename: String

    /// Whether this document is a positive sample (should match the document type)
    public let isPositiveSample: Bool

    /// Whether the model predicted this as a match
    public let predictedIsMatch: Bool

    /// Whether all extracted fields are correct (only meaningful if categorization is correct)
    public let extractionCorrect: Bool

    /// Whether categorization AND extraction are both fully correct
    public var isFullyCorrect: Bool {
        let categorizationCorrect = isPositiveSample == predictedIsMatch
        return categorizationCorrect && extractionCorrect
    }

    public init(
        filename: String,
        isPositiveSample: Bool,
        predictedIsMatch: Bool,
        extractionCorrect: Bool
    ) {
        self.filename = filename
        self.isPositiveSample = isPositiveSample
        self.predictedIsMatch = predictedIsMatch
        self.extractionCorrect = extractionCorrect
    }
}

/// Computed metrics for a benchmark run
public struct BenchmarkMetrics: Equatable {
    /// Overall accuracy (correct / total)
    public let accuracy: Double

    /// Precision (TP / (TP + FP)) - nil if no predicted positives
    public let precision: Double?

    /// Recall (TP / (TP + FN)) - nil if no actual positives
    public let recall: Double?

    /// F1 Score (harmonic mean of precision and recall) - nil if either is nil
    public let f1Score: Double?

    /// Whether the corpus included negative samples
    public let hasNegativeSamples: Bool

    /// Number of true positives
    public let truePositives: Int

    /// Number of false positives
    public let falsePositives: Int

    /// Number of true negatives
    public let trueNegatives: Int

    /// Number of false negatives
    public let falseNegatives: Int

    /// Compute metrics from document results
    public static func compute(from results: [DocumentResult]) -> BenchmarkMetrics {
        guard !results.isEmpty else {
            return .empty
        }

        let counts = classifyCounts(from: results)
        let total = counts.truePos + counts.falsePos + counts.trueNeg + counts.falseNeg
        let accuracy = total > 0 ? Double(counts.truePos + counts.trueNeg) / Double(total) : 0

        let precision: Double? = (counts.truePos + counts.falsePos) > 0
            ? Double(counts.truePos) / Double(counts.truePos + counts.falsePos) : nil
        let recall: Double? = (counts.truePos + counts.falseNeg) > 0
            ? Double(counts.truePos) / Double(counts.truePos + counts.falseNeg) : nil

        let f1Score: Double? = if let prec = precision, let rec = recall, (prec + rec) > 0 {
            2 * prec * rec / (prec + rec)
        } else {
            nil
        }

        return BenchmarkMetrics(
            accuracy: accuracy,
            precision: precision,
            recall: recall,
            f1Score: f1Score,
            hasNegativeSamples: results.contains { !$0.isPositiveSample },
            truePositives: counts.truePos,
            falsePositives: counts.falsePos,
            trueNegatives: counts.trueNeg,
            falseNegatives: counts.falseNeg
        )
    }

    /// Empty metrics for zero-document case
    static let empty = BenchmarkMetrics(
        accuracy: 0, precision: nil, recall: nil, f1Score: nil,
        hasNegativeSamples: false,
        truePositives: 0, falsePositives: 0, trueNegatives: 0, falseNegatives: 0
    )

    private struct ConfusionCounts {
        var truePos = 0
        var falsePos = 0
        var trueNeg = 0
        var falseNeg = 0
    }

    private static func classifyCounts(from results: [DocumentResult]) -> ConfusionCounts {
        var counts = ConfusionCounts()
        for result in results {
            if result.isPositiveSample {
                if result.isFullyCorrect { counts.truePos += 1 } else { counts.falseNeg += 1 }
            } else {
                if !result.predictedIsMatch { counts.trueNeg += 1 } else { counts.falsePos += 1 }
            }
        }
        return counts
    }
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
