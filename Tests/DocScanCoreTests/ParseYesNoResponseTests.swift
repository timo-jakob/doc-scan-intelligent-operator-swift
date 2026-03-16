@testable import DocScanCore
import XCTest

final class ParseYesNoResponseTests: XCTestCase {
    // MARK: - Positive Cases

    func testExactYes() {
        XCTAssertTrue(DocumentDetector.parseYesNoResponse("yes"))
    }

    func testExactYesUppercase() {
        XCTAssertTrue(DocumentDetector.parseYesNoResponse("YES"))
    }

    func testExactYesMixedCase() {
        XCTAssertTrue(DocumentDetector.parseYesNoResponse("Yes"))
    }

    func testExactJa() {
        XCTAssertTrue(DocumentDetector.parseYesNoResponse("ja"))
    }

    func testExactJaUppercase() {
        XCTAssertTrue(DocumentDetector.parseYesNoResponse("JA"))
    }

    func testYesWithTrailingWhitespace() {
        XCTAssertTrue(DocumentDetector.parseYesNoResponse("  yes  "))
    }

    func testYesWithNewlines() {
        XCTAssertTrue(DocumentDetector.parseYesNoResponse("\nyes\n"))
    }

    func testYesWithTrailingPunctuation() {
        XCTAssertTrue(DocumentDetector.parseYesNoResponse("yes."))
    }

    func testYesWithExclamationMark() {
        XCTAssertTrue(DocumentDetector.parseYesNoResponse("Yes!"))
    }

    func testYesPrefixedWithComma() {
        XCTAssertTrue(DocumentDetector.parseYesNoResponse("yes, this is an invoice"))
    }

    func testYesPrefixedWithSpace() {
        XCTAssertTrue(DocumentDetector.parseYesNoResponse("yes this is an invoice"))
    }

    func testJaPrefixedWithComma() {
        XCTAssertTrue(DocumentDetector.parseYesNoResponse("ja, das ist eine Rechnung"))
    }

    func testJaPrefixedWithSpace() {
        XCTAssertTrue(DocumentDetector.parseYesNoResponse("ja das ist eine Rechnung"))
    }

    // MARK: - Negative Cases

    func testExactNo() {
        XCTAssertFalse(DocumentDetector.parseYesNoResponse("no"))
    }

    func testExactNoUppercase() {
        XCTAssertFalse(DocumentDetector.parseYesNoResponse("NO"))
    }

    func testExactNein() {
        XCTAssertFalse(DocumentDetector.parseYesNoResponse("nein"))
    }

    func testEmptyString() {
        XCTAssertFalse(DocumentDetector.parseYesNoResponse(""))
    }

    func testWhitespaceOnly() {
        XCTAssertFalse(DocumentDetector.parseYesNoResponse("   "))
    }

    func testRandomText() {
        XCTAssertFalse(DocumentDetector.parseYesNoResponse("This is a document"))
    }

    func testYesEmbeddedInWord() {
        // "yesterday" starts with "yes" but should not match because no comma/space after "yes"
        XCTAssertFalse(DocumentDetector.parseYesNoResponse("yesterday"))
    }

    func testNoWithExplanation() {
        XCTAssertFalse(DocumentDetector.parseYesNoResponse("no, this is not an invoice"))
    }

    func testNeinWithExplanation() {
        XCTAssertFalse(DocumentDetector.parseYesNoResponse("nein, das ist keine Rechnung"))
    }
}
