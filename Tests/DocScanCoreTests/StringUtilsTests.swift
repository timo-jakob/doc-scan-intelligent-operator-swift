@testable import DocScanCore
import XCTest

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
            ("Burger King GmbH", "Burger_King_GmbH"),
        ]

        for (input, expected) in examples {
            let result = StringUtils.sanitizeCompanyName(input)
            XCTAssertEqual(result, expected, "Failed for input: \(input)")
        }
    }

    // MARK: - Doctor Name Sanitization Tests

    func testSanitizeDoctorNameSimple() {
        let result = StringUtils.sanitizeDoctorName("Gesine Kaiser")
        XCTAssertEqual(result, "Gesine_Kaiser")
    }

    func testSanitizeDoctorNameWithDrTitle() {
        let result = StringUtils.sanitizeDoctorName("Dr. Gesine Kaiser")
        XCTAssertEqual(result, "Gesine_Kaiser")
    }

    func testSanitizeDoctorNameWithDrMedTitle() {
        let result = StringUtils.sanitizeDoctorName("Dr. med. Gesine Kaiser")
        XCTAssertEqual(result, "Gesine_Kaiser")
    }

    func testSanitizeDoctorNameWithDrMedNoSpace() {
        let result = StringUtils.sanitizeDoctorName("Dr.med. Gesine Kaiser")
        XCTAssertEqual(result, "Gesine_Kaiser")
    }

    func testSanitizeDoctorNameWithProfDr() {
        let result = StringUtils.sanitizeDoctorName("Prof. Dr. Hans Müller")
        XCTAssertEqual(result, "Hans_Müller")
    }

    func testSanitizeDoctorNameWithProfDrNoSpaces() {
        let result = StringUtils.sanitizeDoctorName("Prof.Dr. Hans Müller")
        XCTAssertEqual(result, "Hans_Müller")
    }

    func testSanitizeDoctorNameWithMedTitle() {
        let result = StringUtils.sanitizeDoctorName("med. Peter Schmidt")
        XCTAssertEqual(result, "Peter_Schmidt")
    }

    func testSanitizeDoctorNameCaseInsensitive() {
        let result = StringUtils.sanitizeDoctorName("DR. MED. Anna Weber")
        XCTAssertEqual(result, "Anna_Weber")
    }

    func testSanitizeDoctorNameWithSpecialChars() {
        let result = StringUtils.sanitizeDoctorName("Dr. Test: Name/Example")
        XCTAssertEqual(result, "Test_NameExample")
    }

    func testSanitizeDoctorNameWithMultipleSpaces() {
        let result = StringUtils.sanitizeDoctorName("Dr.    Hans    Müller")
        XCTAssertEqual(result, "Hans_Müller")
    }

    func testSanitizeDoctorNameWithLeadingTrailingSpaces() {
        // Note: Leading spaces prevent title removal (title must be at start)
        let result = StringUtils.sanitizeDoctorName("  Dr. Hans Müller  ")
        XCTAssertEqual(result, "Dr._Hans_Müller")

        // Title at start is removed correctly
        let result2 = StringUtils.sanitizeDoctorName("Dr. Hans Müller  ")
        XCTAssertEqual(result2, "Hans_Müller")
    }

    func testSanitizeDoctorNameLongString() {
        let longName = "Dr. " + String(repeating: "A", count: 50)
        let result = StringUtils.sanitizeDoctorName(longName)
        XCTAssertEqual(result.count, 40) // Max doctor name length
    }

    func testSanitizeDoctorNameEmpty() {
        let result = StringUtils.sanitizeDoctorName("")
        XCTAssertEqual(result, "")
    }

    func testSanitizeDoctorNameOnlyTitle() {
        let result = StringUtils.sanitizeDoctorName("Dr.")
        XCTAssertEqual(result, "")
    }

    func testSanitizeDoctorNameWithUmlauts() {
        let result = StringUtils.sanitizeDoctorName("Dr. med. Jörg Müller-Schäfer")
        XCTAssertEqual(result, "Jörg_Müller-Schäfer")
    }

    func testSanitizeDoctorNameRealExamples() {
        let examples: [(input: String, expected: String)] = [
            ("Dr. med. Gesine Kaiser", "Gesine_Kaiser"),
            ("Prof. Dr. med. Hans Weber", "Hans_Weber"),
            ("Dr.med. Anna Schmidt", "Anna_Schmidt"),
            ("Gesine Kaiser", "Gesine_Kaiser"),
            ("Dr. Peter Müller-Schmidt", "Peter_Müller-Schmidt"),
        ]

        for (input, expected) in examples {
            let result = StringUtils.sanitizeDoctorName(input)
            XCTAssertEqual(result, expected, "Failed for input: \(input)")
        }
    }
}

// MARK: - Patient Name Sanitization Tests

extension StringUtilsTests {
    func testSanitizePatientNameSimple() {
        let result = StringUtils.sanitizePatientName("Penelope")
        XCTAssertEqual(result, "Penelope")
    }

    func testSanitizePatientNameWithSpaces() {
        let result = StringUtils.sanitizePatientName("Anna Maria")
        XCTAssertEqual(result, "Anna_Maria")
    }

    func testSanitizePatientNameWithSpecialChars() {
        let result = StringUtils.sanitizePatientName("Test: Name/Example")
        XCTAssertEqual(result, "Test_NameExample")
    }

    func testSanitizePatientNameWithMultipleSpaces() {
        let result = StringUtils.sanitizePatientName("Anna    Maria")
        XCTAssertEqual(result, "Anna_Maria")
    }

    func testSanitizePatientNameWithLeadingTrailingSpaces() {
        let result = StringUtils.sanitizePatientName("  Penelope  ")
        XCTAssertEqual(result, "Penelope")
    }

    func testSanitizePatientNameLongString() {
        let longName = String(repeating: "A", count: 50)
        let result = StringUtils.sanitizePatientName(longName)
        XCTAssertEqual(result.count, 30) // Max patient name length
    }

    func testSanitizePatientNameEmpty() {
        let result = StringUtils.sanitizePatientName("")
        XCTAssertEqual(result, "")
    }

    func testSanitizePatientNameWithUmlauts() {
        let result = StringUtils.sanitizePatientName("Jörg")
        XCTAssertEqual(result, "Jörg")
    }

    func testSanitizePatientNameRealExamples() {
        let examples: [(input: String, expected: String)] = [
            ("Penelope", "Penelope"),
            ("Anna Maria", "Anna_Maria"),
            ("Hans-Peter", "Hans-Peter"),
            ("Müller", "Müller"),
            ("Test Name", "Test_Name"),
        ]

        for (input, expected) in examples {
            let result = StringUtils.sanitizePatientName(input)
            XCTAssertEqual(result, expected, "Failed for input: \(input)")
        }
    }
}
