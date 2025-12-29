import Foundation

/// Shared string utilities for consistent text handling across the codebase
public enum StringUtils {
    /// Characters that are invalid in filenames
    private static let invalidFilenameChars = CharacterSet(charactersIn: ":/\\?%*|\"<>")

    /// Maximum length for company names in filenames
    private static let maxCompanyNameLength = 50

    /// Maximum length for doctor names in filenames
    private static let maxDoctorNameLength = 40

    /// Common doctor title prefixes to remove
    private static let doctorTitles = [
        "dr. med.", "dr.med.", "dr med", "drmed",
        "dr.", "dr",
        "prof. dr.", "prof.dr.", "prof dr",
        "med.", "med"
    ]

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

    /// Sanitize a doctor name for use in filenames
    /// Removes titles like "Dr.", "Dr. med.", "Prof." and formats for filename use
    /// - Parameter name: The raw doctor name (may include titles)
    /// - Returns: A sanitized string with just the name, safe for use in filenames
    public static func sanitizeDoctorName(_ name: String) -> String {
        var sanitized = name

        // Remove doctor titles (case-insensitive)
        for title in doctorTitles {
            // Match title at start of string (case-insensitive)
            if sanitized.lowercased().hasPrefix(title) {
                sanitized = String(sanitized.dropFirst(title.count))
                    .trimmingCharacters(in: .whitespaces)
            }
        }

        // Remove special characters problematic in filenames
        sanitized = sanitized.components(separatedBy: invalidFilenameChars).joined()

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
        return String(underscored.prefix(maxDoctorNameLength))
    }
}
