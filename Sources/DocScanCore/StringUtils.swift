import Foundation

/// Shared string utilities for consistent text handling across the codebase
public enum StringUtils {
    /// Characters that are invalid in filenames
    private static let invalidFilenameChars = CharacterSet(charactersIn: ":/\\?%*|\"<>")

    /// Maximum length for company names in filenames
    private static let maxCompanyNameLength = 50

    /// Maximum length for doctor names in filenames
    private static let maxDoctorNameLength = 40

    /// Maximum length for patient names in filenames
    private static let maxPatientNameLength = 30

    /// Common doctor title prefixes to remove
    private static let doctorTitles = [
        "dr. med.", "dr.med.", "dr med", "drmed",
        "dr.", "dr",
        "prof. dr.", "prof.dr.", "prof dr",
        "med.", "med",
    ]

    /// Sanitize a company name for use in filenames
    /// - Parameter name: The raw company name
    /// - Returns: A sanitized string safe for use in filenames
    public static func sanitizeCompanyName(_ name: String) -> String {
        sanitizeForFilename(name, maxLength: maxCompanyNameLength)
    }

    /// Sanitize a doctor name for use in filenames
    /// Removes titles like "Dr.", "Dr. med.", "Prof." and formats for filename use
    /// - Parameter name: The raw doctor name (may include titles)
    /// - Returns: A sanitized string with just the name, safe for use in filenames
    public static func sanitizeDoctorName(_ name: String) -> String {
        var cleaned = name
        for title in doctorTitles where cleaned.lowercased().hasPrefix(title) {
            cleaned = String(cleaned.dropFirst(title.count))
                .trimmingCharacters(in: .whitespaces)
        }
        return sanitizeForFilename(cleaned, maxLength: maxDoctorNameLength)
    }

    /// Sanitize a patient name (first name) for use in filenames
    /// - Parameter name: The raw patient first name
    /// - Returns: A sanitized string safe for use in filenames
    public static func sanitizePatientName(_ name: String) -> String {
        sanitizeForFilename(name, maxLength: maxPatientNameLength)
    }

    /// Common sanitization pipeline: remove invalid chars, normalize whitespace,
    /// replace spaces with underscores, and truncate.
    private static func sanitizeForFilename(_ name: String, maxLength: Int) -> String {
        let cleaned = name.components(separatedBy: invalidFilenameChars).joined()
        let singleSpaced = cleaned.replacingOccurrences(
            of: "\\s+",
            with: " ",
            options: .regularExpression
        )
        let trimmed = singleSpaced.trimmingCharacters(in: .whitespaces)
        let underscored = trimmed.replacingOccurrences(of: " ", with: "_")
        return String(underscored.prefix(maxLength))
    }
}
