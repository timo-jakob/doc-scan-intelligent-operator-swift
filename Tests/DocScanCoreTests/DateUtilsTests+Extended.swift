@testable import DocScanCore
import XCTest

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
                XCTAssertEqual(
                    components.month,
                    expectedMonth,
                    "Month mismatch for: \(text)"
                )
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
                XCTAssertEqual(
                    components.month,
                    expectedMonth,
                    "Month mismatch for: \(text)"
                )
            }
        }
    }

    func testExtractGermanMonthFromTextCaseInsensitive() {
        let variations = [
            "september 2023",
            "SEPTEMBER 2023",
            "September 2023",
            "sEpTeMbEr 2023",
        ]
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
