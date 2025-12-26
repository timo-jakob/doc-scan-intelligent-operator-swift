import Foundation

/// Shared date parsing utilities for consistent date handling across the codebase
public enum DateUtils {
    /// Supported date formats in priority order
    /// - ISO format first (most unambiguous)
    /// - European format second (common in German invoices)
    /// - Slash formats last (ambiguous between US/EU)
    private static let dateFormats = [
        "yyyy-MM-dd",   // ISO: 2024-12-22
        "dd.MM.yyyy",   // European: 22.12.2024
        "dd/MM/yyyy",   // European with slashes: 22/12/2024
        "MM/dd/yyyy"    // US format: 12/22/2024
    ]

    /// Parse a date string using multiple format attempts
    /// - Parameter dateString: The string to parse
    /// - Returns: A Date if parsing succeeds, nil otherwise
    public static func parseDate(_ dateString: String) -> Date? {
        let trimmed = dateString.trimmingCharacters(in: .whitespaces)

        for format in dateFormats {
            let formatter = DateFormatter()
            formatter.dateFormat = format
            formatter.locale = Locale(identifier: "en_US_POSIX")

            if let date = formatter.date(from: trimmed) {
                return date
            }
        }

        return nil
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
