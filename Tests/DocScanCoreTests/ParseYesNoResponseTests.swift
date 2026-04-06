@testable import DocScanCore
import XCTest

final class ParseYesNoResponseTests: XCTestCase {
    // MARK: - Positive Cases

    func testExactYes() {
        XCTAssertTrue(StringUtils.parseYesNoResponse("yes"))
    }

    func testExactYesUppercase() {
        XCTAssertTrue(StringUtils.parseYesNoResponse("YES"))
    }

    func testExactYesMixedCase() {
        XCTAssertTrue(StringUtils.parseYesNoResponse("Yes"))
    }

    func testExactJa() {
        XCTAssertTrue(StringUtils.parseYesNoResponse("ja"))
    }

    func testExactJaUppercase() {
        XCTAssertTrue(StringUtils.parseYesNoResponse("JA"))
    }

    func testYesWithTrailingWhitespace() {
        XCTAssertTrue(StringUtils.parseYesNoResponse("  yes  "))
    }

    func testYesWithNewlines() {
        XCTAssertTrue(StringUtils.parseYesNoResponse("\nyes\n"))
    }

    func testYesWithTrailingPunctuation() {
        XCTAssertTrue(StringUtils.parseYesNoResponse("yes."))
    }

    func testYesWithExclamationMark() {
        XCTAssertTrue(StringUtils.parseYesNoResponse("Yes!"))
    }

    func testYesPrefixedWithComma() {
        XCTAssertTrue(StringUtils.parseYesNoResponse("yes, this is an invoice"))
    }

    func testYesPrefixedWithSpace() {
        XCTAssertTrue(StringUtils.parseYesNoResponse("yes this is an invoice"))
    }

    func testJaPrefixedWithComma() {
        XCTAssertTrue(StringUtils.parseYesNoResponse("ja, das ist eine Rechnung"))
    }

    func testJaPrefixedWithSpace() {
        XCTAssertTrue(StringUtils.parseYesNoResponse("ja das ist eine Rechnung"))
    }

    // MARK: - Negative Cases

    func testExactNo() {
        XCTAssertFalse(StringUtils.parseYesNoResponse("no"))
    }

    func testExactNoUppercase() {
        XCTAssertFalse(StringUtils.parseYesNoResponse("NO"))
    }

    func testExactNein() {
        XCTAssertFalse(StringUtils.parseYesNoResponse("nein"))
    }

    func testEmptyString() {
        XCTAssertFalse(StringUtils.parseYesNoResponse(""))
    }

    func testWhitespaceOnly() {
        XCTAssertFalse(StringUtils.parseYesNoResponse("   "))
    }

    func testRandomText() {
        XCTAssertFalse(StringUtils.parseYesNoResponse("This is a document"))
    }

    func testYesEmbeddedInWord() {
        // "yesterday" starts with "yes" but should not match because no comma/space after "yes"
        XCTAssertFalse(StringUtils.parseYesNoResponse("yesterday"))
    }

    func testNoWithExplanation() {
        XCTAssertFalse(StringUtils.parseYesNoResponse("no, this is not an invoice"))
    }

    func testNeinWithExplanation() {
        XCTAssertFalse(StringUtils.parseYesNoResponse("nein, das ist keine Rechnung"))
    }
}
