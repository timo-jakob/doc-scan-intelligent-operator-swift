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

    /// Common doctor title prefixes to remove (sorted by descending length for correct matching)
    private static let doctorTitles: [String] = [
        "dr. med.", "dr.med.", "dr med", "drmed",
        "dr.", "dr",
        "prof. dr.", "prof.dr.", "prof dr",
        "med.", "med",
    ].sorted { $0.count > $1.count }

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
        var lowered = cleaned.lowercased()
        var didStrip = true
        while didStrip {
            didStrip = false
            for title in doctorTitles where lowered.hasPrefix(title) {
                cleaned = String(cleaned.dropFirst(title.count))
                    .trimmingCharacters(in: .whitespaces)
                lowered = cleaned.lowercased()
                didStrip = true
                break
            }
        }
        return sanitizeForFilename(cleaned, maxLength: maxDoctorNameLength)
    }

    /// Sanitize a patient name (first name) for use in filenames
    /// - Parameter name: The raw patient first name
    /// - Returns: A sanitized string safe for use in filenames
    public static func sanitizePatientName(_ name: String) -> String {
        sanitizeForFilename(name, maxLength: maxPatientNameLength)
    }

    // MARK: - Whitespace regex (pre-compiled for performance)

    /// Pre-compiled regex for normalizing whitespace in filenames
    private static let whitespaceRegex: NSRegularExpression = {
        guard let regex = try? NSRegularExpression(pattern: "\\s+") else {
            preconditionFailure("Invalid whitespace regex pattern")
        }
        return regex
    }()

    // MARK: - VLM Response Parsing

    /// Parse a YES/NO response from a VLM.
    ///
    /// Strips whitespace and punctuation, then checks for exact match or common prefixed forms.
    /// Returns `true` for "yes"/"ja" variants, `false` for everything else.
    public static func parseYesNoResponse(_ response: String) -> Bool {
        let trimmed = response
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .trimmingCharacters(in: .punctuationCharacters)

        if trimmed == "yes" || trimmed == "ja" { return true }
        if trimmed.hasPrefix("yes,") || trimmed.hasPrefix("yes ") { return true }
        if trimmed.hasPrefix("ja,") || trimmed.hasPrefix("ja ") { return true }
        return false
    }

    // MARK: - Filename Sanitization

    /// Common sanitization pipeline: remove invalid chars, normalize whitespace,
    /// replace spaces with underscores, and truncate.
    private static func sanitizeForFilename(_ name: String, maxLength: Int) -> String {
        let cleaned = name.components(separatedBy: invalidFilenameChars).joined()
        let range = NSRange(cleaned.startIndex..., in: cleaned)
        let singleSpaced = whitespaceRegex.stringByReplacingMatches(
            in: cleaned, range: range, withTemplate: " ",
        )
        let trimmed = singleSpaced.trimmingCharacters(in: .whitespaces)
        let underscored = trimmed.replacingOccurrences(of: " ", with: "_")
        return String(underscored.prefix(maxLength))
    }
}
