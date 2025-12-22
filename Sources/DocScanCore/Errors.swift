import Foundation

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

    public var errorDescription: String? {
        switch self {
        case .invalidPDF(let message):
            return "Invalid PDF: \(message)"
        case .pdfConversionFailed(let message):
            return "Failed to convert PDF: \(message)"
        case .modelLoadFailed(let message):
            return "Failed to load model: \(message)"
        case .modelNotFound(let message):
            return "Model not found: \(message)"
        case .inferenceError(let message):
            return "Inference error: \(message)"
        case .fileNotFound(let path):
            return "File not found: \(path)"
        case .fileOperationFailed(let message):
            return "File operation failed: \(message)"
        case .configurationError(let message):
            return "Configuration error: \(message)"
        case .notAnInvoice:
            return "Document is not an invoice"
        case .extractionFailed(let message):
            return "Failed to extract invoice data: \(message)"
        case .insufficientDiskSpace(let required, let available):
            let requiredGB = Double(required) / 1_000_000_000
            let availableGB = Double(available) / 1_000_000_000
            return String(format: "Insufficient disk space: %.2f GB required, %.2f GB available",
                        requiredGB, availableGB)
        }
    }
}
