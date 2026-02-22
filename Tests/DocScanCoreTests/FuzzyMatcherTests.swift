@testable import DocScanCore
import XCTest

final class FuzzyMatcherTests: XCTestCase {
    // MARK: - datesMatch

    func testDatesMatchSameISO() {
        XCTAssertTrue(FuzzyMatcher.datesMatch("2025-06-27", "2025-06-27"))
    }

    func testDatesMatchISOvsEuropean() {
        XCTAssertTrue(FuzzyMatcher.datesMatch("2025-06-27", "27.06.2025"))
    }

    func testDatesMatchISOvsSlash() {
        XCTAssertTrue(FuzzyMatcher.datesMatch("2025-06-27", "27/06/2025"))
    }

    func testDatesMatchDifferentDates() {
        XCTAssertFalse(FuzzyMatcher.datesMatch("2025-06-27", "2025-07-27"))
    }

    func testDatesMatchBothNil() {
        XCTAssertTrue(FuzzyMatcher.datesMatch(nil, nil))
    }

    func testDatesMatchOneNil() {
        XCTAssertFalse(FuzzyMatcher.datesMatch("2025-06-27", nil))
        XCTAssertFalse(FuzzyMatcher.datesMatch(nil, "2025-06-27"))
    }

    func testDatesMatchUnparseableStrings() {
        XCTAssertFalse(FuzzyMatcher.datesMatch("not-a-date", "2025-06-27"))
    }

    // MARK: - numbersMatch

    func testNumbersMatchIntegerVsDecimal() {
        XCTAssertTrue(FuzzyMatcher.numbersMatch("1.0", "1"))
    }

    func testNumbersMatchTrailingZeros() {
        XCTAssertTrue(FuzzyMatcher.numbersMatch("1.00", "1"))
    }

    func testNumbersMatchSameDecimal() {
        XCTAssertTrue(FuzzyMatcher.numbersMatch("3.14", "3.14"))
    }

    func testNumbersMatchDifferent() {
        XCTAssertFalse(FuzzyMatcher.numbersMatch("1", "2"))
    }

    func testNumbersMatchBothNil() {
        XCTAssertTrue(FuzzyMatcher.numbersMatch(nil, nil))
    }

    func testNumbersMatchOneNil() {
        XCTAssertFalse(FuzzyMatcher.numbersMatch("1", nil))
        XCTAssertFalse(FuzzyMatcher.numbersMatch(nil, "1"))
    }

    // MARK: - fieldsMatch

    func testFieldsMatchExact() {
        XCTAssertTrue(FuzzyMatcher.fieldsMatch("DB Fernverkehr AG", "DB Fernverkehr AG"))
    }

    func testFieldsMatchUnderscoreVsSpace() {
        XCTAssertTrue(FuzzyMatcher.fieldsMatch("DB Fernverkehr AG", "DB_Fernverkehr_AG"))
    }

    func testFieldsMatchCaseInsensitive() {
        XCTAssertTrue(FuzzyMatcher.fieldsMatch("DB Fernverkehr AG", "db fernverkehr ag"))
    }

    func testFieldsMatchAllNormalization() {
        XCTAssertTrue(FuzzyMatcher.fieldsMatch("DB_Fernverkehr_AG", "db fernverkehr ag"))
    }

    func testFieldsMatchBothNil() {
        XCTAssertTrue(FuzzyMatcher.fieldsMatch(nil, nil))
    }

    func testFieldsMatchOneNil() {
        XCTAssertFalse(FuzzyMatcher.fieldsMatch(nil, "something"))
        XCTAssertFalse(FuzzyMatcher.fieldsMatch("something", nil))
    }

    func testFieldsMatchLeadingTrailingWhitespace() {
        XCTAssertTrue(FuzzyMatcher.fieldsMatch("  Company  ", "Company"))
    }

    func testFieldsMatchDifferentValues() {
        XCTAssertFalse(FuzzyMatcher.fieldsMatch("Company A", "Company B"))
    }

    // MARK: - documentIsCorrect

    func testDocumentIsCorrectAllCorrect() {
        let gt = GroundTruth(
            isMatch: true,
            documentType: .invoice,
            date: "2025-06-27",
            secondaryField: "DB_Fernverkehr_AG"
        )
        XCTAssertTrue(FuzzyMatcher.documentIsCorrect(
            expected: gt,
            actualIsMatch: true,
            actualDate: "27.06.2025",
            actualSecondaryField: "db fernverkehr ag",
            actualPatientName: nil
        ))
    }

    func testDocumentIsCorrectWrongCategorization() {
        let gt = GroundTruth(
            isMatch: true,
            documentType: .invoice,
            date: "2025-06-27",
            secondaryField: "Company"
        )
        XCTAssertFalse(FuzzyMatcher.documentIsCorrect(
            expected: gt,
            actualIsMatch: false,
            actualDate: "2025-06-27",
            actualSecondaryField: "Company",
            actualPatientName: nil
        ))
    }

    func testDocumentIsCorrectWrongDate() {
        let gt = GroundTruth(
            isMatch: true,
            documentType: .invoice,
            date: "2025-06-27",
            secondaryField: "Company"
        )
        XCTAssertFalse(FuzzyMatcher.documentIsCorrect(
            expected: gt,
            actualIsMatch: true,
            actualDate: "2025-07-27",
            actualSecondaryField: "Company",
            actualPatientName: nil
        ))
    }

    func testDocumentIsCorrectWrongSecondaryField() {
        let gt = GroundTruth(
            isMatch: true,
            documentType: .invoice,
            date: "2025-06-27",
            secondaryField: "Company_A"
        )
        XCTAssertFalse(FuzzyMatcher.documentIsCorrect(
            expected: gt,
            actualIsMatch: true,
            actualDate: "2025-06-27",
            actualSecondaryField: "Company_B",
            actualPatientName: nil
        ))
    }

    func testDocumentIsCorrectWrongPatientName() {
        let gt = GroundTruth(
            isMatch: true,
            documentType: .prescription,
            date: "2025-04-08",
            secondaryField: "Kaiser",
            patientName: "Penelope"
        )
        XCTAssertFalse(FuzzyMatcher.documentIsCorrect(
            expected: gt,
            actualIsMatch: true,
            actualDate: "2025-04-08",
            actualSecondaryField: "Kaiser",
            actualPatientName: "Charlotte"
        ))
    }

    func testDocumentIsCorrectCategorizationWrongButFieldsRight() {
        let gt = GroundTruth(
            isMatch: false,
            documentType: .invoice
        )
        // actualIsMatch is true but expected is false -> incorrect
        XCTAssertFalse(FuzzyMatcher.documentIsCorrect(
            expected: gt,
            actualIsMatch: true,
            actualDate: nil,
            actualSecondaryField: nil,
            actualPatientName: nil
        ))
    }

    func testDocumentIsCorrectBothNotMatch() {
        let gt = GroundTruth(
            isMatch: false,
            documentType: .invoice
        )
        // Both agree it's not a match -> correct (no fields to check)
        XCTAssertTrue(FuzzyMatcher.documentIsCorrect(
            expected: gt,
            actualIsMatch: false,
            actualDate: nil,
            actualSecondaryField: nil,
            actualPatientName: nil
        ))
    }
}
