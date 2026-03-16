@testable import DocScanCore
import XCTest

/// Tests for DocumentDetector filename generation with prescription-specific placeholder logic.
/// Covers the applyPrescriptionPlaceholders method paths.
final class PrescriptionFilenameTests: XCTestCase {
    private func makeDetector(documentType: DocumentType = .prescription) -> DocumentDetector {
        DocumentDetector(
            config: Configuration.defaultConfiguration,
            documentType: documentType,
            vlmProvider: MockVLMProvider(),
            textLLM: MockTextLLMProvider()
        )
    }

    private func date(_ string: String) -> Date? {
        DateUtils.parseDate(string)
    }

    // MARK: - Prescription: Both Patient and Doctor Present

    func testPrescriptionFilenameAllFields() {
        let detector = makeDetector()
        let data = DocumentData(
            documentType: .prescription,
            isMatch: true,
            date: date("2025-04-08"),
            secondaryField: "Gesine_Kaiser",
            patientName: "Max"
        )

        let filename = detector.generateFilename(from: data)
        XCTAssertEqual(filename, "2025-04-08_Rezept_für_Max_von_Gesine_Kaiser.pdf")
    }

    // MARK: - Prescription: Patient Only (No Doctor)

    func testPrescriptionFilenamePatientOnly() {
        let detector = makeDetector()
        let data = DocumentData(
            documentType: .prescription,
            isMatch: true,
            date: date("2025-04-08"),
            secondaryField: nil,
            patientName: "Max"
        )

        let filename = detector.generateFilename(from: data)
        // {doctor} placeholder removal: "_von_{doctor}" → ""
        XCTAssertEqual(filename, "2025-04-08_Rezept_für_Max.pdf")
    }

    // MARK: - Prescription: Doctor Only (No Patient)

    func testPrescriptionFilenameDoctorOnly() {
        let detector = makeDetector()
        let data = DocumentData(
            documentType: .prescription,
            isMatch: true,
            date: date("2025-04-08"),
            secondaryField: "Mueller",
            patientName: nil
        )

        let filename = detector.generateFilename(from: data)
        // {patient} placeholder removal: "für_{patient}_" → ""
        XCTAssertEqual(filename, "2025-04-08_Rezept_von_Mueller.pdf")
    }

    // MARK: - Prescription: Neither Patient nor Doctor

    func testPrescriptionFilenameNoPatientNoDoctor() {
        let detector = makeDetector()
        let data = DocumentData(
            documentType: .prescription,
            isMatch: true,
            date: date("2025-04-08"),
            secondaryField: nil,
            patientName: nil
        )

        let filename = detector.generateFilename(from: data)
        // Both removed: "für_{patient}_" → "" and "_von_{doctor}" → ""
        XCTAssertEqual(filename, "2025-04-08_Rezept.pdf")
    }

    // MARK: - Prescription: Not a Match

    func testPrescriptionFilenameNotMatch() {
        let detector = makeDetector()
        let data = DocumentData(
            documentType: .prescription,
            isMatch: false,
            date: date("2025-04-08"),
            secondaryField: "Mueller",
            patientName: "Max"
        )

        let filename = detector.generateFilename(from: data)
        XCTAssertNil(filename)
    }

    // MARK: - Prescription: Missing Date

    func testPrescriptionFilenameMissingDate() {
        let detector = makeDetector()
        let data = DocumentData(
            documentType: .prescription,
            isMatch: true,
            date: nil,
            secondaryField: "Mueller",
            patientName: "Max"
        )

        let filename = detector.generateFilename(from: data)
        XCTAssertNil(filename)
    }

    // MARK: - Invoice: Company Required

    func testInvoiceFilenameRequiresCompany() {
        let detector = DocumentDetector(
            config: Configuration.defaultConfiguration,
            documentType: .invoice,
            vlmProvider: MockVLMProvider(),
            textLLM: MockTextLLMProvider()
        )
        let data = DocumentData(
            documentType: .invoice,
            isMatch: true,
            date: date("2025-06-27"),
            secondaryField: nil // Missing company
        )

        let filename = detector.generateFilename(from: data)
        XCTAssertNil(filename)
    }

    func testInvoiceFilenameSuccess() {
        let detector = DocumentDetector(
            config: Configuration.defaultConfiguration,
            documentType: .invoice,
            vlmProvider: MockVLMProvider(),
            textLLM: MockTextLLMProvider()
        )
        let data = DocumentData(
            documentType: .invoice,
            isMatch: true,
            date: date("2025-06-27"),
            secondaryField: "DB_Fernverkehr_AG"
        )

        let filename = detector.generateFilename(from: data)
        XCTAssertEqual(filename, "2025-06-27_Rechnung_DB_Fernverkehr_AG.pdf")
    }
}
