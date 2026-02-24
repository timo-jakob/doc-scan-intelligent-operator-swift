import Foundation

/// Timeout error for async operations
public struct TimeoutError: Error, LocalizedError {
    public var errorDescription: String? {
        "Operation timed out"
    }

    /// Execute an async operation with a timeout.
    ///
    /// If the operation does not cooperatively check `Task.isCancelled`,
    /// this function will wait for the operation to complete even after timeout.
    /// For truly non-cancellable operations (e.g. MLX inference), consider
    /// subprocess-level isolation instead.
    public static func withTimeout<T: Sendable>(
        seconds: TimeInterval,
        operation: @Sendable @escaping () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await operation() }
            group.addTask {
                try await Task.sleep(for: .seconds(seconds))
                throw TimeoutError()
            }
            guard let result = try await group.next() else {
                group.cancelAll()
                throw TimeoutError()
            }
            group.cancelAll()
            // Drain remaining tasks to ensure cleanup completes
            while !group.isEmpty {
                _ = try? await group.next()
            }
            return result
        }
    }
}

/// Errors that can occur during document scanning and processing
public enum DocScanError: LocalizedError {
    case invalidPDF(String)
    case pdfConversionFailed(String)
    case modelLoadFailed(String)
    case modelNotFound(String)
    case inferenceError(String)
    case fileNotFound(String)
    case fileOperationFailed(String)
    case configurationError(String)
    case documentTypeMismatch(String)
    case extractionFailed(String)
    case insufficientDiskSpace(required: UInt64, available: UInt64)
    case invalidInput(String)
    case keychainError(String)
    case networkError(String)
    case huggingFaceAPIError(String)
    case benchmarkError(String)
    case memoryInsufficient(required: UInt64, available: UInt64)

    public var errorDescription: String? {
        switch self {
        case let .invalidPDF(message):
            return "Invalid PDF: \(message)"
        case let .pdfConversionFailed(message):
            return "Failed to convert PDF: \(message)"
        case let .modelLoadFailed(message):
            return "Failed to load model: \(message)"
        case let .modelNotFound(message):
            return "Model not found: \(message)"
        case let .inferenceError(message):
            return "Inference error: \(message)"
        case let .fileNotFound(path):
            return "File not found: \(path)"
        case let .fileOperationFailed(message):
            return "File operation failed: \(message)"
        case let .configurationError(message):
            return "Configuration error: \(message)"
        case let .documentTypeMismatch(typeName):
            return "Document does not match type: \(typeName)"
        case let .extractionFailed(message):
            return "Failed to extract document data: \(message)"
        case let .insufficientDiskSpace(required, available):
            let requiredGB = Double(required) / 1_000_000_000
            let availableGB = Double(available) / 1_000_000_000
            return String(format: "Insufficient disk space: %.2f GB required, %.2f GB available",
                          requiredGB, availableGB)
        case let .invalidInput(message):
            return "Invalid input: \(message)"
        case let .keychainError(message):
            return "Keychain error: \(message)"
        case let .networkError(message):
            return "Network error: \(message)"
        case let .huggingFaceAPIError(message):
            return "Hugging Face API error: \(message)"
        case let .benchmarkError(message):
            return "Benchmark error: \(message)"
        case let .memoryInsufficient(required, available):
            let requiredMB = Double(required) / 1_000_000
            let availableMB = Double(available) / 1_000_000
            return String(format: "Insufficient memory: %.0f MB required, %.0f MB available",
                          requiredMB, availableMB)
        }
    }
}
