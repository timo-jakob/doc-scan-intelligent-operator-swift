import Foundation

/// Timeout error for async operations
public struct TimeoutError: Error, LocalizedError {
    public var errorDescription: String? {
        return "Operation timed out"
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
    case notAnInvoice
    case extractionFailed(String)
    case insufficientDiskSpace(required: UInt64, available: UInt64)
    case invalidInput(String)

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
        case .notAnInvoice:
            return "Document is not an invoice"
        case let .extractionFailed(message):
            return "Failed to extract invoice data: \(message)"
        case let .insufficientDiskSpace(required, available):
            let requiredGB = Double(required) / 1_000_000_000
            let availableGB = Double(available) / 1_000_000_000
            return String(format: "Insufficient disk space: %.2f GB required, %.2f GB available",
                          requiredGB, availableGB)
        case let .invalidInput(message):
            return "Invalid input: \(message)"
        }
    }
}
