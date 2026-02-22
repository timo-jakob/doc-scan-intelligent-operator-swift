import Foundation

/// Fuzzy comparison utilities for benchmark scoring
public enum FuzzyMatcher {
    /// Compare two date strings by parsing them into Date objects
    /// Returns true if both parse to the same calendar date, or both are nil
    public static func datesMatch(_ expected: String?, _ actual: String?) -> Bool {
        switch (expected, actual) {
        case (nil, nil):
            return true
        case (nil, _), (_, nil):
            return false
        case let (e?, a?):
            guard let expectedDate = DateUtils.parseDate(e, validate: false),
                  let actualDate = DateUtils.parseDate(a, validate: false)
            else {
                return false
            }
            let calendar = Calendar.current
            return calendar.isDate(expectedDate, inSameDayAs: actualDate)
        }
    }

    /// Compare two numeric strings with tolerance
    /// Returns true if both parse to the same Double value
    public static func numbersMatch(_ expected: String?, _ actual: String?) -> Bool {
        switch (expected, actual) {
        case (nil, nil):
            return true
        case (nil, _), (_, nil):
            return false
        case let (e?, a?):
            guard let expectedNum = Double(e.trimmingCharacters(in: .whitespaces)),
                  let actualNum = Double(a.trimmingCharacters(in: .whitespaces))
            else {
                return false
            }
            return abs(expectedNum - actualNum) < 0.001
        }
    }

    /// Compare two field strings with fuzzy matching:
    /// - Case-insensitive
    /// - Whitespace-normalized
    /// - Underscore/space equivalent
    public static func fieldsMatch(_ expected: String?, _ actual: String?) -> Bool {
        switch (expected, actual) {
        case (nil, nil):
            return true
        case (nil, _), (_, nil):
            return false
        case let (e?, a?):
            let normalizedExpected = normalizeField(e)
            let normalizedActual = normalizeField(a)
            return normalizedExpected == normalizedActual
        }
    }

    /// Check if a document result is fully correct against ground truth
    /// Categorization AND all fields must match
    public static func documentIsCorrect(
        expected: GroundTruth,
        actualIsMatch: Bool,
        actualDate: String?,
        actualSecondaryField: String?,
        actualPatientName: String?
    ) -> Bool {
        // Categorization must match
        guard expected.isMatch == actualIsMatch else {
            return false
        }

        // If not a match, no further fields to check
        guard expected.isMatch else {
            return true
        }

        // All fields must match
        guard datesMatch(expected.date, actualDate) else {
            return false
        }
        guard fieldsMatch(expected.secondaryField, actualSecondaryField) else {
            return false
        }
        guard fieldsMatch(expected.patientName, actualPatientName) else {
            return false
        }

        return true
    }

    /// Normalize a field string for comparison
    private static func normalizeField(_ field: String) -> String {
        field
            .lowercased()
            .trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: "_", with: " ")
            .components(separatedBy: .whitespaces)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}
