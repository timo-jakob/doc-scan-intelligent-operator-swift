import Foundation
import os

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
        "MM/dd/yyyy", // US format: 12/22/2024
    ]

    /// Regex patterns for extracting dates from text
    private static let datePatterns = [
        "\\b(\\d{4})-(\\d{2})-(\\d{2})\\b", // ISO: 2024-12-22
        "\\b(\\d{2})[./](\\d{2})[./](\\d{4})\\b", // European: 22.12.2024
        "\\b(\\d{2}):(\\d{2}):(\\d{4})\\b", // Colon-separated: 22:12:2024
        "\\b(\\d{2})/(\\d{2})/(\\d{4})\\b", // US: 12/22/2024
    ]

    /// Keywords that typically precede invoice dates
    private static let dateKeywords = [
        "rechnungsdatum:", "invoice date:", "datum:", "date:",
        "rechnungsdatum", "invoice date", "facture du:", "fecha:",
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
        "dezember": 12, "dez": 12, "dec": 12,
    ]

    /// German month names as array for text searching (ordered by length for proper matching)
    private static let germanMonthNames = [
        "januar", "februar", "märz", "maerz", "april", "mai", "juni",
        "juli", "august", "september", "oktober", "november", "dezember",
        "jan", "feb", "mrz", "apr", "jun", "jul", "aug", "sep", "sept", "okt", "nov", "dez",
    ]

    // MARK: - Cached Formatters & Regex

    /// Thread-safe DateFormatter cache. DateFormatter is not thread-safe, so all
    /// parse/format operations are performed under the lock.
    private static let formatterStore = OSAllocatedUnfairLock(
        initialState: FormatterState()
    )

    /// Internal state for the formatter cache
    private struct FormatterState {
        /// Formatters for the standard date formats (used in parseDate)
        let standardFormatters: [DateFormatter] = dateFormats.map { format in
            let formatter = DateFormatter()
            formatter.dateFormat = format
            formatter.locale = Locale(identifier: "en_US_POSIX")
            return formatter
        }

        /// ISO formatter for formatDate fast-path
        let isoFormatter: DateFormatter = {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            formatter.locale = Locale(identifier: "en_US_POSIX")
            return formatter
        }()

        /// Custom formatters keyed by format string
        var customFormatters: [String: DateFormatter] = [:]
    }

    /// Cached gregorian calendar to avoid repeated `Calendar.current` lookups
    private static let calendar = Calendar(identifier: .gregorian)

    /// Cached NSRegularExpression instances (one per date pattern), compiled once
    private static let cachedDateRegexes: [NSRegularExpression] = datePatterns.compactMap { pattern in
        try? NSRegularExpression(pattern: pattern)
    }

    /// Cached year regex for German month/year parsing.
    /// NSRegularExpression is used instead of Swift Regex because Regex is not Sendable in Swift 6.
    private static let yearRegex: NSRegularExpression = // swiftlint:disable:next force_try
        try! NSRegularExpression(pattern: "\\b(20\\d{2})\\b")

    /// Cached word-boundary regexes for German month name matching (one per month name)
    private static let germanMonthRegexes: [(String, NSRegularExpression)] = germanMonthNames.compactMap { month in
        let pattern = "\\b\(NSRegularExpression.escapedPattern(for: month))\\b"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
            return nil
        }
        return (month, regex)
    }

    /// Parse a date string using multiple format attempts
    /// - Parameter dateString: The string to parse
    /// - Parameter validate: Whether to validate the date is reasonable (default: true)
    /// - Returns: A Date if parsing succeeds and is valid, nil otherwise
    public static func parseDate(_ dateString: String, validate: Bool = true) -> Date? {
        let trimmed = dateString.trimmingCharacters(in: .whitespaces)

        // Try standard formats first (locked for DateFormatter thread safety)
        let standardResult: Date? = formatterStore.withLock { state in
            for formatter in state.standardFormatters {
                if let date = formatter.date(from: trimmed) {
                    if validate, !isValidDate(date) {
                        continue
                    }
                    return date
                }
            }
            return nil
        }
        if let date = standardResult {
            return date
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
            // Extract year (4 digits) using cached regex
            guard let match = yearRegex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
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

            return calendar.date(from: components)
        }

        return nil
    }

    /// Validate that a date is reasonable for an invoice
    /// - Rejects dates before 2000
    /// - Rejects dates more than 2 years in the future
    public static func isValidDate(_ date: Date) -> Bool {
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
        formatterStore.withLock { state in
            if format == "yyyy-MM-dd" {
                return state.isoFormatter.string(from: date)
            }
            if let cached = state.customFormatters[format] {
                return cached.string(from: date)
            }
            // Cap cache size to prevent unbounded growth
            if state.customFormatters.count > 20 { state.customFormatters.removeAll() }
            let formatter = DateFormatter()
            formatter.dateFormat = format
            formatter.locale = Locale(identifier: "en_US_POSIX")
            state.customFormatters[format] = formatter
            return formatter.string(from: date)
        }
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

                // Try numeric patterns near keywords (using cached regexes)
                for regex in cachedDateRegexes {
                    if let date = extractDateWithCachedRegex(nearbyText, regex: regex) {
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

        // Strategy 3: Fallback - try any numeric date pattern in the text (using cached regexes)
        for regex in cachedDateRegexes {
            if let date = extractDateWithCachedRegex(text, regex: regex) {
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

        for (month, monthRegex) in germanMonthRegexes {
            // Use cached word boundary regex to avoid false positives
            let searchRange = NSRange(lowercased.startIndex..., in: lowercased)
            guard let monthMatch = monthRegex.firstMatch(
                in: lowercased, range: searchRange
            ),
                let monthRange = Range(monthMatch.range, in: lowercased)
            else {
                continue
            }

            // Look for a 4-digit year after the month (using cached regex)
            let afterMonthString = String(String(lowercased[monthRange.upperBound...]).prefix(20))

            let yearRange2 = NSRange(
                afterMonthString.startIndex..., in: afterMonthString
            )
            guard let yearMatch = yearRegex.firstMatch(
                in: afterMonthString, range: yearRange2
            ),
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

    /// Extract a date using a pre-compiled regex (internal fast path)
    private static func extractDateWithCachedRegex(_ text: String, regex: NSRegularExpression) -> Date? {
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

    /// Extract a date using a specific regex pattern
    /// - Parameters:
    ///   - text: The text to search
    ///   - pattern: The regex pattern to match
    /// - Returns: A Date if the pattern matches and parses successfully, nil otherwise
    public static func extractDateWithPattern(_ text: String, pattern: String) -> Date? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }
        return extractDateWithCachedRegex(text, regex: regex)
    }
}
