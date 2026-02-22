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

    // MARK: - scoreDocument

    func testScoreDocumentAllCorrect() {
        let groundTruth = GroundTruth(
            isMatch: true,
            documentType: .invoice,
            date: "2025-06-27",
            secondaryField: "DB_Fernverkehr_AG"
        )
        let scoring = FuzzyMatcher.scoreDocument(
            expected: groundTruth,
            actualIsMatch: true,
            actualDate: "27.06.2025",
            actualSecondaryField: "db fernverkehr ag",
            actualPatientName: nil
        )
        XCTAssertTrue(scoring.categorizationCorrect)
        XCTAssertTrue(scoring.extractionCorrect)
        XCTAssertEqual(scoring.score, 2)
    }

    func testScoreDocumentWrongCategorization() {
        let groundTruth = GroundTruth(
            isMatch: true,
            documentType: .invoice,
            date: "2025-06-27",
            secondaryField: "Company"
        )
        let scoring = FuzzyMatcher.scoreDocument(
            expected: groundTruth,
            actualIsMatch: false,
            actualDate: "2025-06-27",
            actualSecondaryField: "Company",
            actualPatientName: nil
        )
        XCTAssertFalse(scoring.categorizationCorrect)
        XCTAssertFalse(scoring.extractionCorrect)
        XCTAssertEqual(scoring.score, 0)
    }

    func testScoreDocumentCorrectCategorizationWrongDate() {
        let groundTruth = GroundTruth(
            isMatch: true,
            documentType: .invoice,
            date: "2025-06-27",
            secondaryField: "Company"
        )
        let scoring = FuzzyMatcher.scoreDocument(
            expected: groundTruth,
            actualIsMatch: true,
            actualDate: "2025-07-27",
            actualSecondaryField: "Company",
            actualPatientName: nil
        )
        XCTAssertTrue(scoring.categorizationCorrect)
        XCTAssertFalse(scoring.extractionCorrect)
        XCTAssertEqual(scoring.score, 1)
    }

    func testScoreDocumentCorrectCategorizationWrongSecondaryField() {
        let groundTruth = GroundTruth(
            isMatch: true,
            documentType: .invoice,
            date: "2025-06-27",
            secondaryField: "Company_A"
        )
        let scoring = FuzzyMatcher.scoreDocument(
            expected: groundTruth,
            actualIsMatch: true,
            actualDate: "2025-06-27",
            actualSecondaryField: "Company_B",
            actualPatientName: nil
        )
        XCTAssertTrue(scoring.categorizationCorrect)
        XCTAssertFalse(scoring.extractionCorrect)
        XCTAssertEqual(scoring.score, 1)
    }

    func testScoreDocumentWrongPatientName() {
        let groundTruth = GroundTruth(
            isMatch: true,
            documentType: .prescription,
            date: "2025-04-08",
            secondaryField: "Kaiser",
            patientName: "Penelope"
        )
        let scoring = FuzzyMatcher.scoreDocument(
            expected: groundTruth,
            actualIsMatch: true,
            actualDate: "2025-04-08",
            actualSecondaryField: "Kaiser",
            actualPatientName: "Charlotte"
        )
        XCTAssertTrue(scoring.categorizationCorrect)
        XCTAssertFalse(scoring.extractionCorrect)
        XCTAssertEqual(scoring.score, 1)
    }

    func testScoreDocumentFalsePositive() {
        let groundTruth = GroundTruth(
            isMatch: false,
            documentType: .invoice
        )
        let scoring = FuzzyMatcher.scoreDocument(
            expected: groundTruth,
            actualIsMatch: true,
            actualDate: nil,
            actualSecondaryField: nil,
            actualPatientName: nil
        )
        XCTAssertFalse(scoring.categorizationCorrect)
        XCTAssertFalse(scoring.extractionCorrect)
        XCTAssertEqual(scoring.score, 0)
    }

    func testScoreDocumentCorrectRejection() {
        let groundTruth = GroundTruth(
            isMatch: false,
            documentType: .invoice
        )
        let scoring = FuzzyMatcher.scoreDocument(
            expected: groundTruth,
            actualIsMatch: false,
            actualDate: nil,
            actualSecondaryField: nil,
            actualPatientName: nil
        )
        XCTAssertTrue(scoring.categorizationCorrect)
        XCTAssertTrue(scoring.extractionCorrect)
        XCTAssertEqual(scoring.score, 2)
    }
}
