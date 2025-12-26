import Foundation

/// Shared string utilities for consistent text handling across the codebase
public enum StringUtils {
    /// Characters that are invalid in filenames
    private static let invalidFilenameChars = CharacterSet(charactersIn: ":/\\?%*|\"<>")

    /// Maximum length for company names in filenames
    private static let maxCompanyNameLength = 50

    /// Sanitize a company name for use in filenames
    /// - Parameter name: The raw company name
    /// - Returns: A sanitized string safe for use in filenames
    public static func sanitizeCompanyName(_ name: String) -> String {
        // Remove special characters problematic in filenames
        let sanitized = name.components(separatedBy: invalidFilenameChars).joined()

        // Replace multiple spaces with single space
        let singleSpaced = sanitized.replacingOccurrences(
            of: "\\s+",
            with: " ",
            options: .regularExpression
        )

        // Trim whitespace
        let trimmed = singleSpaced.trimmingCharacters(in: .whitespaces)

        // Replace spaces with underscores for cleaner filenames
        let underscored = trimmed.replacingOccurrences(of: " ", with: "_")

        // Limit length to avoid overly long filenames
        return String(underscored.prefix(maxCompanyNameLength))
    }
}
