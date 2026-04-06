@testable import DocScanCore
import XCTest

/// Direct unit tests for TextLLMManager.parseExtractionResponse and regex fallback
final class TextLLMParsingDirectTests: XCTestCase {
    private var manager: TextLLMManager!

    override func setUp() {
        super.setUp()
        manager = TextLLMManager(config: Configuration())
    }

    override func tearDown() {
        manager = nil
        super.tearDown()
    }

    // MARK: - Well-formed invoice response

    func testParseInvoiceAllFields() async {
        let response = """
        DATE: 2024-03-15
        COMPANY: Deutsche Bahn AG
        """
        let result = await manager.parseExtractionResponse(response, documentType: .invoice)
        XCTAssertNotNil(result.date)
        XCTAssertEqual(result.secondaryField, "Deutsche_Bahn_AG")
        XCTAssertNil(result.patientName)
    }

    func testParseInvoiceDateOnly() async {
        let response = """
        DATE: 2024-01-10
        COMPANY: NOT_FOUND
        """
        let result = await manager.parseExtractionResponse(response, documentType: .invoice)
        XCTAssertNotNil(result.date)
        XCTAssertNil(result.secondaryField, "NOT_FOUND should be rejected")
    }

    func testParseInvoiceNoFields() async {
        let response = """
        DATE: UNKNOWN
        COMPANY: UNKNOWN
        """
        let result = await manager.parseExtractionResponse(response, documentType: .invoice)
        XCTAssertNil(result.date)
        XCTAssertNil(result.secondaryField)
    }

    // MARK: - Well-formed prescription response

    func testParsePrescriptionAllFields() async {
        let response = """
        PATIENT: Anna
        DATE: 2025-04-08
        DOCTOR: Gesine Kaiser
        """
        let result = await manager.parseExtractionResponse(response, documentType: .prescription)
        XCTAssertNotNil(result.date)
        XCTAssertEqual(result.secondaryField, "Gesine_Kaiser")
        XCTAssertEqual(result.patientName, "Anna")
    }

    func testParsePrescriptionDoctorOnly() async {
        let response = """
        PATIENT: NOT_FOUND
        DATE: NOT_FOUND
        DOCTOR: Mueller
        """
        let result = await manager.parseExtractionResponse(response, documentType: .prescription)
        XCTAssertNil(result.date)
        XCTAssertEqual(result.secondaryField, "Mueller")
        XCTAssertNil(result.patientName)
    }

    // MARK: - Edge cases

    func testParseExtraWhitespace() async {
        let response = """
        DATE:   2024-06-01
        COMPANY:   Some Corp
        """
        let result = await manager.parseExtractionResponse(response, documentType: .invoice)
        XCTAssertNotNil(result.date)
        XCTAssertEqual(result.secondaryField, "Some_Corp")
    }

    func testParseEmptyResponse() async {
        let result = await manager.parseExtractionResponse("", documentType: .invoice)
        XCTAssertNil(result.date)
        XCTAssertNil(result.secondaryField)
    }

    func testParsePrescriptionIgnoresCompanyPrefix() async {
        let response = """
        DATE: 2024-01-01
        COMPANY: Should Be Ignored
        DOCTOR: Schmidt
        """
        let result = await manager.parseExtractionResponse(response, documentType: .prescription)
        // COMPANY: line should be ignored for prescription type — only DOCTOR: is recognized
        XCTAssertEqual(result.secondaryField, "Schmidt", "Only DOCTOR: should be extracted for prescriptions")
    }

    // MARK: - Path traversal guard test

    func testFileRenamerPathTraversalGuard() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("docscan-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let testFile = tempDir.appendingPathComponent("test.pdf")
        try "test".write(to: testFile, atomically: true, encoding: .utf8)

        let renamer = FileRenamer(verbose: false)
        XCTAssertThrowsError(try renamer.rename(
            from: testFile.path, to: "../../malicious.pdf",
        )) { error in
            guard let docError = error as? DocScanError,
                  case let .fileOperationFailed(msg) = docError
            else {
                XCTFail("Expected DocScanError.fileOperationFailed")
                return
            }
            XCTAssertTrue(msg.contains("escape source directory"))
        }
    }

    // MARK: - ProcessingSettings validation boundaries

    func testValidateMaxTokensZero() {
        let settings = ProcessingSettings(maxTokens: 0)
        XCTAssertThrowsError(try settings.validate())
    }

    func testValidateTemperatureNegative() {
        let settings = ProcessingSettings(temperature: -0.1)
        XCTAssertThrowsError(try settings.validate())
    }

    func testValidateTemperatureAboveMax() {
        let settings = ProcessingSettings(temperature: 2.01)
        XCTAssertThrowsError(try settings.validate())
    }

    func testValidateTemperatureAtMax() throws {
        let settings = ProcessingSettings(temperature: 2.0)
        XCTAssertNoThrow(try settings.validate())
    }

    func testValidatePdfDPIZero() {
        let settings = ProcessingSettings(pdfDPI: 0)
        XCTAssertThrowsError(try settings.validate())
    }

    // MARK: - German month false positive prevention

    func testGermanMonthFalsePositiveEmail() {
        // "mai" in "email" should not produce a false match
        let result = DateUtils.extractGermanMonthFromText("contact@email.com 2024")
        XCTAssertNil(result)
    }

    // MARK: - sanitizeDoctorName multi-title stripping

    func testSanitizeDoctorNameMultipleTitles() {
        let result = StringUtils.sanitizeDoctorName("Prof. Dr. med. Schmidt")
        XCTAssertEqual(result, "Schmidt")
    }

    func testSanitizeDoctorNameSingleTitle() {
        let result = StringUtils.sanitizeDoctorName("Dr. Mueller")
        XCTAssertEqual(result, "Mueller")
    }

    // MARK: - parseYesNoResponse shared utility

    func testParseYesNoResponseGermanPunctuation() {
        XCTAssertTrue(StringUtils.parseYesNoResponse("Ja."))
        XCTAssertTrue(StringUtils.parseYesNoResponse("JA!"))
        XCTAssertTrue(StringUtils.parseYesNoResponse("ja"))
        XCTAssertFalse(StringUtils.parseYesNoResponse("Nein."))
        XCTAssertFalse(StringUtils.parseYesNoResponse(""))
    }

    // MARK: - Boundary success tests for ProcessingSettings

    func testValidateMaxTokensOne() throws {
        let settings = ProcessingSettings(maxTokens: 1)
        XCTAssertNoThrow(try settings.validate())
    }

    func testValidatePdfDPIOne() throws {
        let settings = ProcessingSettings(pdfDPI: 1)
        XCTAssertNoThrow(try settings.validate())
    }

    // MARK: - DocumentType metadata properties

    func testDocumentTypeSecondaryFieldEmoji() {
        XCTAssertEqual(DocumentType.invoice.secondaryFieldEmoji, "🏢")
        XCTAssertEqual(DocumentType.prescription.secondaryFieldEmoji, "👨‍⚕️")
    }

    func testDocumentTypeIsSecondaryFieldRequired() {
        XCTAssertTrue(DocumentType.invoice.isSecondaryFieldRequired)
        XCTAssertFalse(DocumentType.prescription.isSecondaryFieldRequired)
    }

    func testDocumentTypeHasPatientField() {
        XCTAssertFalse(DocumentType.invoice.hasPatientField)
        XCTAssertTrue(DocumentType.prescription.hasPatientField)
    }

    func testDocumentTypeSecondaryFieldLabel() {
        XCTAssertEqual(DocumentType.invoice.secondaryFieldLabel, "Company")
        XCTAssertEqual(DocumentType.prescription.secondaryFieldLabel, "Doctor")
    }

    func testDocumentTypeTextClassificationSystemPrompt() {
        XCTAssertTrue(DocumentType.textClassificationSystemPrompt.contains("YES or NO"))
    }

    // MARK: - Stronger error assertions

    func testFileRenamerNonExistentFileThrowsFileNotFound() {
        let renamer = FileRenamer(verbose: false)
        XCTAssertThrowsError(try renamer.rename(
            from: "/nonexistent/path.pdf", to: "new.pdf",
        )) { error in
            guard let docError = error as? DocScanError,
                  case .fileNotFound = docError
            else {
                XCTFail("Expected DocScanError.fileNotFound, got: \(error)")
                return
            }
        }
    }

    // MARK: - CategorizationMethod.ocrError

    func testOcrErrorDisplayLabels() {
        let result = CategorizationResult(
            isMatch: false, confidence: .low,
            method: .ocrError, reason: "Test error",
        )
        XCTAssertEqual(result.shortDisplayLabel, "OCR (error)")
        XCTAssertTrue(result.displayLabel.contains("Error"))
        XCTAssertTrue(result.isError)
        XCTAssertFalse(result.isTimedOut)
    }

    // MARK: - renameToDirectory path traversal

    func testRenameToDirectoryPathTraversalGuard() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("docscan-dir-test-\(UUID().uuidString)")
        let targetDir = tempDir.appendingPathComponent("target")
        try FileManager.default.createDirectory(at: targetDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let testFile = tempDir.appendingPathComponent("test.pdf")
        try "test".write(to: testFile, atomically: true, encoding: .utf8)

        let renamer = FileRenamer(verbose: false)
        XCTAssertThrowsError(try renamer.renameToDirectory(
            from: testFile.path, to: targetDir.path,
            filename: "../../escape.pdf",
        )) { error in
            guard let docError = error as? DocScanError,
                  case let .fileOperationFailed(msg) = docError
            else {
                XCTFail("Expected DocScanError.fileOperationFailed")
                return
            }
            XCTAssertTrue(msg.contains("escape target directory"))
        }
    }
}
