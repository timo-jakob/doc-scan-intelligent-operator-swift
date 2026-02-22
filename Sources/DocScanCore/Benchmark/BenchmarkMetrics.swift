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
            return BenchmarkMetrics(
                accuracy: 0,
                precision: nil,
                recall: nil,
                f1Score: nil,
                hasNegativeSamples: false,
                truePositives: 0,
                falsePositives: 0,
                trueNegatives: 0,
                falseNegatives: 0
            )
        }

        var tp = 0, fp = 0, tn = 0, fn = 0

        for result in results {
            if result.isPositiveSample {
                if result.isFullyCorrect {
                    tp += 1
                } else {
                    fn += 1
                }
            } else {
                if !result.predictedIsMatch {
                    tn += 1
                } else {
                    fp += 1
                }
            }
        }

        let total = tp + fp + tn + fn
        let accuracy = total > 0 ? Double(tp + tn) / Double(total) : 0

        let precision: Double? = (tp + fp) > 0 ? Double(tp) / Double(tp + fp) : nil
        let recall: Double? = (tp + fn) > 0 ? Double(tp) / Double(tp + fn) : nil

        let f1Score: Double?
        if let p = precision, let r = recall, (p + r) > 0 {
            f1Score = 2 * p * r / (p + r)
        } else {
            f1Score = nil
        }

        let hasNegatives = results.contains { !$0.isPositiveSample }

        return BenchmarkMetrics(
            accuracy: accuracy,
            precision: precision,
            recall: recall,
            f1Score: f1Score,
            hasNegativeSamples: hasNegatives,
            truePositives: tp,
            falsePositives: fp,
            trueNegatives: tn,
            falseNegatives: fn
        )
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
