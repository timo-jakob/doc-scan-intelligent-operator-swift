import XCTest
@testable import DocScanCore

final class StringUtilsTests: XCTestCase {

    // MARK: - Basic Sanitization Tests

    func testSanitizeCompanyNameSimple() {
        let result = StringUtils.sanitizeCompanyName("Acme Corporation")
        XCTAssertEqual(result, "Acme_Corporation")
    }

    func testSanitizeCompanyNameWithGmbH() {
        let result = StringUtils.sanitizeCompanyName("Test Company GmbH")
        XCTAssertEqual(result, "Test_Company_GmbH")
    }

    func testSanitizeCompanyNameWithAG() {
        let result = StringUtils.sanitizeCompanyName("Deutsche Bank AG")
        XCTAssertEqual(result, "Deutsche_Bank_AG")
    }

    // MARK: - Special Characters Tests

    func testSanitizeCompanyNameWithColon() {
        let result = StringUtils.sanitizeCompanyName("Company: Name")
        XCTAssertEqual(result, "Company_Name")
    }

    func testSanitizeCompanyNameWithSlashes() {
        let result = StringUtils.sanitizeCompanyName("Company/Name\\Test")
        XCTAssertEqual(result, "CompanyNameTest")
    }

    func testSanitizeCompanyNameWithQuestionMark() {
        let result = StringUtils.sanitizeCompanyName("Company? Name")
        XCTAssertEqual(result, "Company_Name")
    }

    func testSanitizeCompanyNameWithAsterisk() {
        let result = StringUtils.sanitizeCompanyName("Company * Name")
        XCTAssertEqual(result, "Company_Name")
    }

    func testSanitizeCompanyNameWithPipe() {
        let result = StringUtils.sanitizeCompanyName("Company | Name")
        XCTAssertEqual(result, "Company_Name")
    }

    func testSanitizeCompanyNameWithQuotes() {
        let result = StringUtils.sanitizeCompanyName("Company \"Name\"")
        XCTAssertEqual(result, "Company_Name")
    }

    func testSanitizeCompanyNameWithAngleBrackets() {
        let result = StringUtils.sanitizeCompanyName("Company <Name>")
        XCTAssertEqual(result, "Company_Name")
    }

    func testSanitizeCompanyNameWithPercent() {
        let result = StringUtils.sanitizeCompanyName("Company % Name")
        XCTAssertEqual(result, "Company_Name")
    }

    func testSanitizeCompanyNameWithAllInvalidChars() {
        let result = StringUtils.sanitizeCompanyName("A:/\\?%*|\"<>Z")
        XCTAssertEqual(result, "AZ")
    }

    // MARK: - Whitespace Tests

    func testSanitizeCompanyNameWithMultipleSpaces() {
        let result = StringUtils.sanitizeCompanyName("Company    Name")
        XCTAssertEqual(result, "Company_Name")
    }

    func testSanitizeCompanyNameWithLeadingSpaces() {
        let result = StringUtils.sanitizeCompanyName("   Company Name")
        XCTAssertEqual(result, "Company_Name")
    }

    func testSanitizeCompanyNameWithTrailingSpaces() {
        let result = StringUtils.sanitizeCompanyName("Company Name   ")
        XCTAssertEqual(result, "Company_Name")
    }

    func testSanitizeCompanyNameWithMixedWhitespace() {
        let result = StringUtils.sanitizeCompanyName("  Company   Name  ")
        XCTAssertEqual(result, "Company_Name")
    }

    func testSanitizeCompanyNameWithTabs() {
        let result = StringUtils.sanitizeCompanyName("Company\t\tName")
        XCTAssertEqual(result, "Company_Name")
    }

    // MARK: - Length Limiting Tests

    func testSanitizeCompanyNameLongString() {
        let longName = String(repeating: "A", count: 100)
        let result = StringUtils.sanitizeCompanyName(longName)
        XCTAssertEqual(result.count, 50)
        XCTAssertEqual(result, String(repeating: "A", count: 50))
    }

    func testSanitizeCompanyNameExactlyMaxLength() {
        let exactName = String(repeating: "B", count: 50)
        let result = StringUtils.sanitizeCompanyName(exactName)
        XCTAssertEqual(result.count, 50)
        XCTAssertEqual(result, exactName)
    }

    func testSanitizeCompanyNameUnderMaxLength() {
        let shortName = "Short Name"
        let result = StringUtils.sanitizeCompanyName(shortName)
        XCTAssertEqual(result, "Short_Name")
        XCTAssertLessThan(result.count, 50)
    }

    // MARK: - Edge Cases

    func testSanitizeCompanyNameEmpty() {
        let result = StringUtils.sanitizeCompanyName("")
        XCTAssertEqual(result, "")
    }

    func testSanitizeCompanyNameOnlySpaces() {
        let result = StringUtils.sanitizeCompanyName("     ")
        XCTAssertEqual(result, "")
    }

    func testSanitizeCompanyNameOnlyInvalidChars() {
        let result = StringUtils.sanitizeCompanyName(":/\\?%*|\"<>")
        XCTAssertEqual(result, "")
    }

    func testSanitizeCompanyNameSingleCharacter() {
        let result = StringUtils.sanitizeCompanyName("A")
        XCTAssertEqual(result, "A")
    }

    func testSanitizeCompanyNameWithNumbers() {
        let result = StringUtils.sanitizeCompanyName("Company 123 GmbH")
        XCTAssertEqual(result, "Company_123_GmbH")
    }

    func testSanitizeCompanyNameWithUmlautsAndSpecialChars() {
        let result = StringUtils.sanitizeCompanyName("Müller & Söhne")
        // Umlauts and & should be preserved (not in invalid set)
        XCTAssertEqual(result, "Müller_&_Söhne")
    }

    func testSanitizeCompanyNameGermanRealWorldExample() {
        let result = StringUtils.sanitizeCompanyName("DB Fernverkehr AG")
        XCTAssertEqual(result, "DB_Fernverkehr_AG")
    }

    func testSanitizeCompanyNameWithNewlines() {
        let result = StringUtils.sanitizeCompanyName("Company\nName")
        // Newlines are whitespace and should be handled
        XCTAssertEqual(result, "Company_Name")
    }

    // MARK: - Real-World Examples

    func testSanitizeCompanyNameRealExamples() {
        let examples: [(input: String, expected: String)] = [
            ("Deutsche Bahn AG", "Deutsche_Bahn_AG"),
            ("Amazon EU S.a.r.l.", "Amazon_EU_S.a.r.l."),
            ("Apple Inc.", "Apple_Inc."),
            ("Bayerische Landesbrandversicherung", "Bayerische_Landesbrandversicherung"),
            ("Burger King GmbH", "Burger_King_GmbH")
        ]

        for (input, expected) in examples {
            let result = StringUtils.sanitizeCompanyName(input)
            XCTAssertEqual(result, expected, "Failed for input: \(input)")
        }
    }
}
