import Foundation

/// Shared date parsing utilities for consistent date handling across the codebase
public enum DateUtils {
    /// Supported date formats in priority order
    /// - ISO format first (most unambiguous)
    /// - European format second (common in German invoices)
    /// - Colon-separated (OCR sometimes reads dots as colons)
    /// - Slash formats last (ambiguous between US/EU)
    private static let dateFormats = [
        "yyyy-MM-dd", // ISO: 2024-12-22
        "dd.MM.yyyy", // European: 22.12.2024
        "dd:MM:yyyy", // Colon-separated (OCR artifact): 22:12:2024
        "dd/MM/yyyy", // European with slashes: 22/12/2024
        "MM/dd/yyyy" // US format: 12/22/2024
    ]

    /// Regex patterns for extracting dates from text
    private static let datePatterns = [
        "\\b(\\d{4})-(\\d{2})-(\\d{2})\\b", // ISO: 2024-12-22
        "\\b(\\d{2})[./](\\d{2})[./](\\d{4})\\b", // European: 22.12.2024
        "\\b(\\d{2}):(\\d{2}):(\\d{4})\\b", // Colon-separated: 22:12:2024
        "\\b(\\d{2})/(\\d{2})/(\\d{4})\\b" // US: 12/22/2024
    ]

    /// Keywords that typically precede invoice dates
    private static let dateKeywords = [
        "rechnungsdatum:", "invoice date:", "datum:", "date:",
        "rechnungsdatum", "invoice date", "facture du:", "fecha:"
    ]

    /// German month names for parsing "September 2022" style dates
    private static let germanMonths: [String: Int] = [
        "januar": 1, "jan": 1,
        "februar": 2, "feb": 2,
        "märz": 3, "maerz": 3, "mar": 3, "mrz": 3,
        "april": 4, "apr": 4,
        "mai": 5,
        "juni": 6, "jun": 6,
        "juli": 7, "jul": 7,
        "august": 8, "aug": 8,
        "september": 9, "sep": 9, "sept": 9,
        "oktober": 10, "okt": 10, "oct": 10,
        "november": 11, "nov": 11,
        "dezember": 12, "dez": 12, "dec": 12
    ]

    /// German month names as array for text searching (ordered by length for proper matching)
    private static let germanMonthNames = [
        "januar", "februar", "märz", "maerz", "april", "mai", "juni",
        "juli", "august", "september", "oktober", "november", "dezember",
        "jan", "feb", "mrz", "apr", "jun", "jul", "aug", "sep", "sept", "okt", "nov", "dez"
    ]

    /// Parse a date string using multiple format attempts
    /// - Parameter dateString: The string to parse
    /// - Parameter validate: Whether to validate the date is reasonable (default: true)
    /// - Returns: A Date if parsing succeeds and is valid, nil otherwise
    public static func parseDate(_ dateString: String, validate: Bool = true) -> Date? {
        let trimmed = dateString.trimmingCharacters(in: .whitespaces)

        // Try standard formats first
        for format in dateFormats {
            let formatter = DateFormatter()
            formatter.dateFormat = format
            formatter.locale = Locale(identifier: "en_US_POSIX")

            if let date = formatter.date(from: trimmed) {
                if validate, !isValidDate(date) {
                    continue // Try other formats
                }
                return date
            }
        }

        // Try German month name format: "September 2022" or "Sep 2022"
        if let date = parseGermanMonthYear(trimmed) {
            if validate, !isValidDate(date) {
                return nil
            }
            return date
        }

        return nil
    }

    /// Parse German month/year format like "September 2022"
    private static func parseGermanMonthYear(_ text: String) -> Date? {
        let lowercased = text.lowercased()

        for (monthName, monthNumber) in germanMonths where lowercased.contains(monthName) {
            // Extract year (4 digits)
            let yearPattern = "\\b(20\\d{2})\\b"
            guard let regex = try? NSRegularExpression(pattern: yearPattern),
                  let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
                  let range = Range(match.range(at: 1), in: text)
            else {
                continue
            }

            let yearString = String(text[range])
            guard let year = Int(yearString) else { continue }

            // Create date for first of that month
            var components = DateComponents()
            components.year = year
            components.month = monthNumber
            components.day = 1

            return Calendar.current.date(from: components)
        }

        return nil
    }

    /// Validate that a date is reasonable for an invoice
    /// - Rejects dates before 2000
    /// - Rejects dates more than 2 years in the future
    public static func isValidDate(_ date: Date) -> Bool {
        let calendar = Calendar.current
        let now = Date()

        // Get year components
        let dateYear = calendar.component(.year, from: date)
        let currentYear = calendar.component(.year, from: now)

        // Reject dates before 2000
        if dateYear < 2000 {
            return false
        }

        // Reject dates more than 2 years in the future
        if dateYear > currentYear + 2 {
            return false
        }

        return true
    }

    /// Format a date to the standard invoice filename format
    /// - Parameters:
    ///   - date: The date to format
    ///   - format: The desired format string (default: yyyy-MM-dd)
    /// - Returns: The formatted date string
    public static func formatDate(_ date: Date, format: String = "yyyy-MM-dd") -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = format
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.string(from: date)
    }

    // MARK: - Text Extraction Functions

    /// Extract a date from text, trying multiple strategies
    /// 1. Look for dates near common keywords (most reliable)
    /// 2. Try German month format anywhere (preferred for billing periods)
    /// 3. Try numeric date patterns anywhere (fallback)
    /// - Parameter text: The text to search for dates
    /// - Returns: The first valid date found, or nil
    public static func extractDateFromText(_ text: String) -> Date? {
        // Strategy 1: Try to find date near common keywords first (more reliable)
        for keyword in dateKeywords {
            if let range = text.range(of: keyword, options: .caseInsensitive) {
                let afterKeyword = String(text[range.upperBound...])
                let nearbyText = String(afterKeyword.prefix(40))

                // Try numeric patterns near keywords
                for pattern in datePatterns {
                    if let date = extractDateWithPattern(nearbyText, pattern: pattern) {
                        return date
                    }
                }

                // Try German month format near keywords
                if let date = extractGermanMonthFromText(nearbyText) {
                    return date
                }
            }
        }

        // Strategy 2: Try German month format anywhere in text FIRST
        // This is preferred over numeric dates because billing period dates like "September 2022"
        // are more likely to be the invoice date than other dates like payment due dates
        if let date = extractGermanMonthFromText(text) {
            return date
        }

        // Strategy 3: Fallback - try any numeric date pattern in the text
        for pattern in datePatterns {
            if let date = extractDateWithPattern(text, pattern: pattern) {
                return date
            }
        }

        return nil
    }

    /// Extract date from German month format like "September 2022"
    /// Uses word boundary matching to avoid false positives (e.g., "mai" in "email")
    /// - Parameter text: The text to search
    /// - Returns: A Date if a German month + year pattern is found, nil otherwise
    public static func extractGermanMonthFromText(_ text: String) -> Date? {
        let lowercased = text.lowercased()

        for month in germanMonthNames {
            // Use word boundary regex to avoid false positives
            let monthPattern = "\\b\(NSRegularExpression.escapedPattern(for: month))\\b"
            guard let monthRegex = try? NSRegularExpression(pattern: monthPattern, options: .caseInsensitive),
                  let monthMatch = monthRegex.firstMatch(in: lowercased, range: NSRange(lowercased.startIndex..., in: lowercased)),
                  let monthRange = Range(monthMatch.range, in: lowercased)
            else {
                continue
            }

            // Look for a 4-digit year after the month
            let afterMonthString = String(String(lowercased[monthRange.upperBound...]).prefix(20))
            let yearPattern = "\\b(20\\d{2})\\b"

            guard let yearRegex = try? NSRegularExpression(pattern: yearPattern),
                  let yearMatch = yearRegex.firstMatch(in: afterMonthString, range: NSRange(afterMonthString.startIndex..., in: afterMonthString)),
                  let yearRange = Range(yearMatch.range, in: afterMonthString)
            else {
                continue
            }

            let yearString = afterMonthString[yearRange]
            let monthYearString = "\(month) \(yearString)"
            if let date = parseDate(monthYearString) {
                return date
            }
        }

        return nil
    }

    /// Extract a date using a specific regex pattern
    /// - Parameters:
    ///   - text: The text to search
    ///   - pattern: The regex pattern to match
    /// - Returns: A Date if the pattern matches and parses successfully, nil otherwise
    public static func extractDateWithPattern(_ text: String, pattern: String) -> Date? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }

        let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))

        for match in matches {
            if let range = Range(match.range, in: text) {
                let dateString = String(text[range])
                if let date = parseDate(dateString) {
                    return date
                }
            }
        }

        return nil
    }
}
