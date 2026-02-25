import Foundation

// MARK: - Memory Estimation

public extension BenchmarkEngine {
    /// Estimate total memory needed for a VLM + text model pair in MB.
    /// Parses parameter counts from model IDs (e.g. "Qwen2-VL-7B" → 7B params).
    /// 4-bit quantized models use ~0.5 bytes/param + ~20% overhead for KV cache and runtime.
    /// Returns 0 if neither model ID contains a recognizable size.
    static func estimateMemoryMB(vlm: String, text: String) -> UInt64 {
        let vlmParams = parseParamBillions(from: vlm)
        let textParams = parseParamBillions(from: text)
        guard vlmParams > 0 || textParams > 0 else { return 0 }
        // 4-bit ≈ 0.5 bytes/param; apply 1.2x overhead for KV cache + runtime buffers
        let bytesPerParam = 0.5 * 1.2
        let totalBytes = (vlmParams + textParams) * bytesPerParam * 1_000_000_000
        return UInt64(totalBytes / 1_000_000)
    }

    /// NSRegularExpression is used instead of Swift Regex because Regex is not Sendable in Swift 6.
    private static let paramBillionsRegex: NSRegularExpression = {
        guard let regex = try? NSRegularExpression(pattern: #"(\d+\.?\d*)\s*[Bb](?:\b|-)"#) else {
            preconditionFailure("Invalid regex pattern for paramBillionsRegex")
        }
        return regex
    }()

    /// Extract parameter count in billions from a model ID string.
    /// Matches patterns like "7B", "2B", "0.5B", "72B" (case-insensitive).
    internal static func parseParamBillions(from modelId: String) -> Double {
        guard let match = paramBillionsRegex.firstMatch(
            in: modelId,
            range: NSRange(modelId.startIndex ..< modelId.endIndex, in: modelId)
        ),
            let range = Range(match.range(at: 1), in: modelId),
            let value = Double(modelId[range])
        else {
            return 0
        }
        return value
    }

    /// Get available system memory in MB.
    /// On Apple Silicon with unified memory, MLX can use most of the physical RAM.
    /// We apply a 0.8 factor to leave headroom for the OS and other running apps.
    static func availableMemoryMB() -> UInt64 {
        UInt64(Double(ProcessInfo.processInfo.physicalMemory) * 0.8 / 1_000_000)
    }
}
