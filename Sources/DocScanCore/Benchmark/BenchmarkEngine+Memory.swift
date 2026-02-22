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

    /// Extract parameter count in billions from a model ID string.
    /// Matches patterns like "7B", "2B", "0.5B", "72B" (case-insensitive).
    internal static func parseParamBillions(from modelId: String) -> Double {
        let pattern = #"(\d+\.?\d*)\s*[Bb](?:\b|-)"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(
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

    /// Get available system memory in MB
    static func availableMemoryMB() -> UInt64 {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &stats) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPtr in
                host_statistics64(mach_host_self(), HOST_VM_INFO64, intPtr, &count)
            }
        }
        guard result == KERN_SUCCESS else {
            return 0
        }
        let pageSize = UInt64(vm_kernel_page_size)
        let free = UInt64(stats.free_count) * pageSize
        let inactive = UInt64(stats.inactive_count) * pageSize
        return (free + inactive) / 1_000_000
    }
}
