@testable import DocScanCore
import XCTest

final class DateUtilsTests: XCTestCase {
    // MARK: - isValidDate Tests

    func testIsValidDateWithinRange() {
        // Dates well within valid range should pass
        let validDates = [
            createDate(year: 2020, month: 6, day: 15),
            createDate(year: 2015, month: 1, day: 1),
            createDate(year: 2023, month: 12, day: 31),
        ]

        for date in validDates {
            XCTAssertTrue(DateUtils.isValidDate(date), "Date \(date) should be valid")
        }
    }

    func testIsValidDateAtLowerBoundary() {
        // Year 2000 is the lower boundary - should be valid
        let boundaryDate = createDate(year: 2000, month: 1, day: 1)
        XCTAssertTrue(DateUtils.isValidDate(boundaryDate), "Year 2000 should be valid (lower boundary)")

        let endOf2000 = createDate(year: 2000, month: 12, day: 31)
        XCTAssertTrue(DateUtils.isValidDate(endOf2000), "End of 2000 should be valid")
    }

    func testIsValidDateBelowLowerBoundary() {
        // Dates before 2000 should be rejected
        let invalidDates = [
            createDate(year: 1999, month: 12, day: 31), // Just before boundary
            createDate(year: 1999, month: 1, day: 1),
            createDate(year: 1990, month: 6, day: 15),
            createDate(year: 1980, month: 1, day: 1),
        ]

        for date in invalidDates {
            XCTAssertFalse(DateUtils.isValidDate(date), "Date in \(Calendar.current.component(.year, from: date)) should be invalid (before 2000)")
        }
    }

    func testIsValidDateAtUpperBoundary() {
        // Current year + 2 should be valid
        let currentYear = Calendar.current.component(.year, from: Date())
        let upperBoundaryDate = createDate(year: currentYear + 2, month: 6, day: 15)
        XCTAssertTrue(DateUtils.isValidDate(upperBoundaryDate), "Year \(currentYear + 2) should be valid (upper boundary)")

        let endOfUpperBoundary = createDate(year: currentYear + 2, month: 12, day: 31)
        XCTAssertTrue(DateUtils.isValidDate(endOfUpperBoundary), "End of \(currentYear + 2) should be valid")
    }

    func testIsValidDateAboveUpperBoundary() {
        // Dates more than 2 years in the future should be rejected
        let currentYear = Calendar.current.component(.year, from: Date())

        let invalidDates = [
            createDate(year: currentYear + 3, month: 1, day: 1), // Just above boundary
            createDate(year: currentYear + 5, month: 6, day: 15),
            createDate(year: currentYear + 10, month: 12, day: 31),
        ]

        for date in invalidDates {
            let year = Calendar.current.component(.year, from: date)
            XCTAssertFalse(DateUtils.isValidDate(date), "Date in \(year) should be invalid (more than 2 years in future)")
        }
    }

    func testIsValidDateCurrentYear() {
        // Current year should always be valid
        let currentYear = Calendar.current.component(.year, from: Date())
        let currentYearDate = createDate(year: currentYear, month: 6, day: 15)
        XCTAssertTrue(DateUtils.isValidDate(currentYearDate), "Current year \(currentYear) should be valid")
    }

    func testIsValidDateNextYear() {
        // Next year should be valid
        let currentYear = Calendar.current.component(.year, from: Date())
        let nextYearDate = createDate(year: currentYear + 1, month: 1, day: 1)
        XCTAssertTrue(DateUtils.isValidDate(nextYearDate), "Next year should be valid")
    }

    // MARK: - parseDate Validation Integration Tests

    func testParseDateRejectsInvalidYears() {
        // When validation is enabled (default), dates outside valid range should return nil
        let invalidDateStrings = [
            "1999-12-31", // Before 2000
            "1990-06-15",
            "01.01.1999",
        ]

        for dateString in invalidDateStrings {
            XCTAssertNil(DateUtils.parseDate(dateString), "Date string '\(dateString)' should be rejected by validation")
        }
    }

    func testParseDateAcceptsValidYears() {
        // Valid dates should parse successfully
        let validDateStrings = [
            "2000-01-01", // Lower boundary
            "2020-06-15",
            "2024-12-31",
        ]

        for dateString in validDateStrings {
            XCTAssertNotNil(DateUtils.parseDate(dateString), "Date string '\(dateString)' should parse successfully")
        }
    }

    func testParseDateWithValidationDisabled() {
        // When validation is disabled, dates outside normal range should still parse
        let date1999 = DateUtils.parseDate("1999-12-31", validate: false)
        XCTAssertNotNil(date1999, "Date should parse when validation is disabled")

        if let date = date1999 {
            let year = Calendar.current.component(.year, from: date)
            XCTAssertEqual(year, 1999)
        }
    }

    func testParseDateWithValidationEnabled() {
        // When validation is enabled, old dates should be rejected
        let date1999Validated = DateUtils.parseDate("1999-12-31", validate: true)
        XCTAssertNil(date1999Validated, "Date 1999 should be rejected when validation is enabled")

        let date2020Validated = DateUtils.parseDate("2020-06-15", validate: true)
        XCTAssertNotNil(date2020Validated, "Date 2020 should be accepted when validation is enabled")
    }

    // MARK: - parseDate Format Tests

    func testParseDateISOFormat() {
        let date = DateUtils.parseDate("2024-12-22")
        XCTAssertNotNil(date)

        if let date {
            let components = Calendar.current.dateComponents([.year, .month, .day], from: date)
            XCTAssertEqual(components.year, 2024)
            XCTAssertEqual(components.month, 12)
            XCTAssertEqual(components.day, 22)
        }
    }

    func testParseDateEuropeanFormat() {
        let date = DateUtils.parseDate("22.12.2024")
        XCTAssertNotNil(date)

        if let date {
            let components = Calendar.current.dateComponents([.year, .month, .day], from: date)
            XCTAssertEqual(components.year, 2024)
            XCTAssertEqual(components.month, 12)
            XCTAssertEqual(components.day, 22)
        }
    }

    func testParseDateColonSeparatedFormat() {
        let date = DateUtils.parseDate("22:12:2024")
        XCTAssertNotNil(date)

        if let date {
            let components = Calendar.current.dateComponents([.year, .month, .day], from: date)
            XCTAssertEqual(components.year, 2024)
            XCTAssertEqual(components.month, 12)
            XCTAssertEqual(components.day, 22)
        }
    }

    func testParseDateGermanMonthFormat() {
        let testCases: [(String, Int, Int)] = [
            ("September 2022", 2022, 9),
            ("Januar 2023", 2023, 1),
            ("Dezember 2024", 2024, 12),
            ("März 2021", 2021, 3),
            ("sep 2022", 2022, 9),
            ("okt 2023", 2023, 10),
        ]

        for (dateString, expectedYear, expectedMonth) in testCases {
            let date = DateUtils.parseDate(dateString)
            XCTAssertNotNil(date, "Should parse '\(dateString)'")

            if let date {
                let components = Calendar.current.dateComponents([.year, .month, .day], from: date)
                XCTAssertEqual(components.year, expectedYear, "Year mismatch for '\(dateString)'")
                XCTAssertEqual(components.month, expectedMonth, "Month mismatch for '\(dateString)'")
                XCTAssertEqual(components.day, 1, "Day should be 1 for month-only format '\(dateString)'")
            }
        }
    }

    func testParseDateInvalidFormat() {
        let invalidDates = [
            "not a date",
            "2024/13/45", // Invalid month/day
            "hello world",
            "",
        ]

        for dateString in invalidDates {
            XCTAssertNil(DateUtils.parseDate(dateString), "'\(dateString)' should not parse as a date")
        }
    }

    // MARK: - formatDate Tests

    func testFormatDateDefault() {
        let date = createDate(year: 2024, month: 12, day: 22)
        let formatted = DateUtils.formatDate(date)
        XCTAssertEqual(formatted, "2024-12-22")
    }

    func testFormatDateCustomFormat() {
        let date = createDate(year: 2024, month: 12, day: 22)

        XCTAssertEqual(DateUtils.formatDate(date, format: "dd.MM.yyyy"), "22.12.2024")
        XCTAssertEqual(DateUtils.formatDate(date, format: "yyyy/MM/dd"), "2024/12/22")
        XCTAssertEqual(DateUtils.formatDate(date, format: "MMMM yyyy"), "December 2024")
    }

    // MARK: - extractDateFromText Tests

    func testExtractDateFromTextWithKeyword() {
        let text = "Rechnungsdatum: 2024-12-15 some other text"
        let date = DateUtils.extractDateFromText(text)

        XCTAssertNotNil(date)
        if let date {
            let components = Calendar.current.dateComponents([.year, .month, .day], from: date)
            XCTAssertEqual(components.year, 2024)
            XCTAssertEqual(components.month, 12)
            XCTAssertEqual(components.day, 15)
        }
    }

    func testExtractDateFromTextWithInvoiceDateKeyword() {
        let text = "Invoice Date: 22.12.2024"
        let date = DateUtils.extractDateFromText(text)

        XCTAssertNotNil(date)
        if let date {
            let components = Calendar.current.dateComponents([.year, .month, .day], from: date)
            XCTAssertEqual(components.year, 2024)
            XCTAssertEqual(components.month, 12)
            XCTAssertEqual(components.day, 22)
        }
    }

    func testExtractDateFromTextWithDatumKeyword() {
        let text = "Datum: 15.06.2023"
        let date = DateUtils.extractDateFromText(text)

        XCTAssertNotNil(date)
        if let date {
            let components = Calendar.current.dateComponents([.year, .month, .day], from: date)
            XCTAssertEqual(components.year, 2023)
            XCTAssertEqual(components.month, 6)
            XCTAssertEqual(components.day, 15)
        }
    }

    func testExtractDateFromTextGermanMonthPreferred() {
        // German month format should be preferred over numeric dates
        let text = "Beitragsrechnung September 2022 - Zahlbar bis 01.10.2022"
        let date = DateUtils.extractDateFromText(text)

        XCTAssertNotNil(date)
        if let date {
            let components = Calendar.current.dateComponents([.year, .month, .day], from: date)
            XCTAssertEqual(components.year, 2022)
            XCTAssertEqual(components.month, 9)
            XCTAssertEqual(components.day, 1)
        }
    }

    func testExtractDateFromTextFallbackToNumericPattern() {
        let text = "Some text without keywords 15.12.2024 more text"
        let date = DateUtils.extractDateFromText(text)

        XCTAssertNotNil(date)
        if let date {
            let components = Calendar.current.dateComponents([.year, .month, .day], from: date)
            XCTAssertEqual(components.year, 2024)
            XCTAssertEqual(components.month, 12)
            XCTAssertEqual(components.day, 15)
        }
    }

    func testExtractDateFromTextNoDateFound() {
        let text = "This text has no date at all"
        let date = DateUtils.extractDateFromText(text)
        XCTAssertNil(date)
    }

    func testExtractDateFromTextEmptyString() {
        let date = DateUtils.extractDateFromText("")
        XCTAssertNil(date)
    }

    func testExtractDateFromTextMultipleKeywords() {
        // Should find the first date near a keyword
        let text = "Rechnungsdatum: 2024-01-15 Zahlungsziel: 2024-02-15"
        let date = DateUtils.extractDateFromText(text)

        XCTAssertNotNil(date)
        if let date {
            let components = Calendar.current.dateComponents([.year, .month, .day], from: date)
            XCTAssertEqual(components.year, 2024)
            XCTAssertEqual(components.month, 1)
            XCTAssertEqual(components.day, 15)
        }
    }

    // MARK: - Helper Methods

    private func createDate(year: Int, month: Int, day: Int) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        return Calendar.current.date(from: components)!
    }
}

// MARK: - extractDateWithPattern and extractGermanMonthFromText Tests

final class DateUtilsPatternTests: XCTestCase {
    func testExtractDateWithPatternISO() {
        let text = "Date is 2024-12-22 here"
        let pattern = "\\b(\\d{4})-(\\d{2})-(\\d{2})\\b"
        let date = DateUtils.extractDateWithPattern(text, pattern: pattern)

        XCTAssertNotNil(date)
        if let date {
            let components = Calendar.current.dateComponents([.year, .month, .day], from: date)
            XCTAssertEqual(components.year, 2024)
            XCTAssertEqual(components.month, 12)
            XCTAssertEqual(components.day, 22)
        }
    }

    func testExtractDateWithPatternEuropean() {
        let text = "Datum: 22.12.2024"
        let pattern = "\\b(\\d{2})[./](\\d{2})[./](\\d{4})\\b"
        let date = DateUtils.extractDateWithPattern(text, pattern: pattern)

        XCTAssertNotNil(date)
        if let date {
            let components = Calendar.current.dateComponents([.year, .month, .day], from: date)
            XCTAssertEqual(components.year, 2024)
            XCTAssertEqual(components.month, 12)
            XCTAssertEqual(components.day, 22)
        }
    }

    func testExtractDateWithPatternNoMatch() {
        let text = "No date here"
        let pattern = "\\b(\\d{4})-(\\d{2})-(\\d{2})\\b"
        let date = DateUtils.extractDateWithPattern(text, pattern: pattern)
        XCTAssertNil(date)
    }

    func testExtractDateWithPatternInvalidRegex() {
        let text = "2024-12-22"
        let pattern = "[invalid(regex" // Invalid regex pattern
        let date = DateUtils.extractDateWithPattern(text, pattern: pattern)
        XCTAssertNil(date)
    }

    func testExtractDateWithPatternMultipleMatches() {
        let text = "First: 2024-01-15 Second: 2024-06-20"
        let pattern = "\\b(\\d{4})-(\\d{2})-(\\d{2})\\b"
        let date = DateUtils.extractDateWithPattern(text, pattern: pattern)

        XCTAssertNotNil(date)
        // Should return the first match
        if let date {
            let components = Calendar.current.dateComponents([.year, .month, .day], from: date)
            XCTAssertEqual(components.year, 2024)
            XCTAssertEqual(components.month, 1)
            XCTAssertEqual(components.day, 15)
        }
    }

    // MARK: - extractGermanMonthFromText Tests

    func testExtractGermanMonthFromTextAllMonths() {
        let testCases: [(String, Int)] = [
            ("Januar 2023", 1),
            ("Februar 2023", 2),
            ("März 2023", 3),
            ("April 2023", 4),
            ("Mai 2023", 5),
            ("Juni 2023", 6),
            ("Juli 2023", 7),
            ("August 2023", 8),
            ("September 2023", 9),
            ("Oktober 2023", 10),
            ("November 2023", 11),
            ("Dezember 2023", 12),
        ]

        for (text, expectedMonth) in testCases {
            let date = DateUtils.extractGermanMonthFromText(text)
            XCTAssertNotNil(date, "Failed to parse: \(text)")
            if let date {
                let components = Calendar.current.dateComponents([.month], from: date)
                XCTAssertEqual(components.month, expectedMonth, "Month mismatch for: \(text)")
            }
        }
    }

    func testExtractGermanMonthFromTextAbbreviations() {
        let testCases: [(String, Int)] = [
            ("Jan 2023", 1),
            ("Feb 2023", 2),
            ("Mrz 2023", 3),
            ("Apr 2023", 4),
            ("Jun 2023", 6),
            ("Jul 2023", 7),
            ("Aug 2023", 8),
            ("Sep 2023", 9),
            ("Sept 2023", 9),
            ("Okt 2023", 10),
            ("Nov 2023", 11),
            ("Dez 2023", 12),
        ]

        for (text, expectedMonth) in testCases {
            let date = DateUtils.extractGermanMonthFromText(text)
            XCTAssertNotNil(date, "Failed to parse: \(text)")
            if let date {
                let components = Calendar.current.dateComponents([.month], from: date)
                XCTAssertEqual(components.month, expectedMonth, "Month mismatch for: \(text)")
            }
        }
    }

    func testExtractGermanMonthFromTextCaseInsensitive() {
        let variations = ["september 2023", "SEPTEMBER 2023", "September 2023", "sEpTeMbEr 2023"]
        for text in variations {
            let date = DateUtils.extractGermanMonthFromText(text)
            XCTAssertNotNil(date, "Failed to parse: \(text)")
            if let date {
                let components = Calendar.current.dateComponents([.month], from: date)
                XCTAssertEqual(components.month, 9)
            }
        }
    }

    func testExtractGermanMonthFromTextInContext() {
        let text = "Ihre Beitragsrechnung für September 2022"
        let date = DateUtils.extractGermanMonthFromText(text)

        XCTAssertNotNil(date)
        if let date {
            let components = Calendar.current.dateComponents([.year, .month], from: date)
            XCTAssertEqual(components.year, 2022)
            XCTAssertEqual(components.month, 9)
        }
    }

    func testExtractGermanMonthFromTextNoYear() {
        let text = "September ohne Jahr"
        let date = DateUtils.extractGermanMonthFromText(text)
        XCTAssertNil(date)
    }

    func testExtractGermanMonthFromTextMaerzAlternative() {
        // "maerz" is alternative spelling for "März"
        let date = DateUtils.extractGermanMonthFromText("Maerz 2023")
        XCTAssertNotNil(date)
        if let date {
            let components = Calendar.current.dateComponents([.month], from: date)
            XCTAssertEqual(components.month, 3)
        }
    }

    func testExtractGermanMonthFromTextNoMatch() {
        let text = "This text has no German month"
        let date = DateUtils.extractGermanMonthFromText(text)
        XCTAssertNil(date)
    }

    func testExtractGermanMonthFromTextFalsePositiveProtection() {
        // "mai" should not match within "email"
        let text = "email 2023"
        let date = DateUtils.extractGermanMonthFromText(text)
        XCTAssertNil(date, "Should not match 'mai' within 'email'")
    }
}
