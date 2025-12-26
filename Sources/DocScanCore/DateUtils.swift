import Foundation

/// Shared date parsing utilities for consistent date handling across the codebase
public enum DateUtils {
    /// Supported date formats in priority order
    /// - ISO format first (most unambiguous)
    /// - European format second (common in German invoices)
    /// - Colon-separated (OCR sometimes reads dots as colons)
    /// - Slash formats last (ambiguous between US/EU)
    private static let dateFormats = [
        "yyyy-MM-dd",   // ISO: 2024-12-22
        "dd.MM.yyyy",   // European: 22.12.2024
        "dd:MM:yyyy",   // Colon-separated (OCR artifact): 22:12:2024
        "dd/MM/yyyy",   // European with slashes: 22/12/2024
        "MM/dd/yyyy"    // US format: 12/22/2024
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
                if validate && !isValidDate(date) {
                    continue // Try other formats
                }
                return date
            }
        }

        // Try German month name format: "September 2022" or "Sep 2022"
        if let date = parseGermanMonthYear(trimmed) {
            if validate && !isValidDate(date) {
                return nil
            }
            return date
        }

        return nil
    }

    /// Parse German month/year format like "September 2022"
    private static func parseGermanMonthYear(_ text: String) -> Date? {
        let lowercased = text.lowercased()

        for (monthName, monthNumber) in germanMonths {
            if lowercased.contains(monthName) {
                // Extract year (4 digits)
                let yearPattern = "\\b(20\\d{2})\\b"
                guard let regex = try? NSRegularExpression(pattern: yearPattern),
                      let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
                      let range = Range(match.range(at: 1), in: text) else {
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
}
