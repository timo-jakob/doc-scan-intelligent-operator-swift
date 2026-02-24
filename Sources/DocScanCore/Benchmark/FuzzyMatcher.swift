import Foundation

/// Per-document scoring breakdown
public struct DocumentScoring: Equatable, Sendable {
    public let categorizationCorrect: Bool
    public let extractionCorrect: Bool
    public var score: Int {
        (categorizationCorrect ? 1 : 0) + (extractionCorrect ? 1 : 0)
    }
}

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
        case let (exp?, act?):
            guard let expectedDate = DateUtils.parseDate(exp, validate: false),
                  let actualDate = DateUtils.parseDate(act, validate: false)
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
        case let (exp?, act?):
            guard let expectedNum = Double(exp.trimmingCharacters(in: .whitespaces)),
                  let actualNum = Double(act.trimmingCharacters(in: .whitespaces))
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
        case let (exp?, act?):
            let normalizedExpected = normalizeField(exp)
            let normalizedActual = normalizeField(act)
            return normalizedExpected == normalizedActual
        }
    }

    /// Score a document result against ground truth (0/1/2 points)
    public static func scoreDocument(
        expected: GroundTruth,
        actualIsMatch: Bool,
        actualDate: String?,
        actualSecondaryField: String?,
        actualPatientName: String?
    ) -> DocumentScoring {
        let categorizationCorrect = (expected.isMatch == actualIsMatch)

        guard categorizationCorrect else {
            return DocumentScoring(categorizationCorrect: false, extractionCorrect: false)
        }

        // Correct rejection of a negative sample — full marks
        guard expected.isMatch else {
            return DocumentScoring(categorizationCorrect: true, extractionCorrect: true)
        }

        // Positive sample: check all fields
        let fieldsCorrect = datesMatch(expected.date, actualDate)
            && fieldsMatch(expected.secondaryField, actualSecondaryField)
            && fieldsMatch(expected.patientName, actualPatientName)

        return DocumentScoring(categorizationCorrect: true, extractionCorrect: fieldsCorrect)
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
