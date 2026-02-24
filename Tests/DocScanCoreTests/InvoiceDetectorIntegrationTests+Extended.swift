import AppKit
@testable import DocScanCore
import PDFKit
import XCTest

// MARK: - Prescription Document Type Tests

extension InvoiceDetectorIntegrationTests {
    func testPrescriptionDetector() {
        let prescriptionDetector = DocumentDetector(config: config, documentType: .prescription)
        XCTAssertEqual(prescriptionDetector.documentType, .prescription)
    }

    func testPrescriptionKeywordDetection() {
        let prescriptionDetector = DocumentDetector(config: config, documentType: .prescription)
        let prescriptionText = """
        Rezept
        Dr. med. Gesine Kaiser
        Patient: Max Mustermann
        Medikament: Ibuprofen 400mg
        """

        let result = prescriptionDetector.categorizeWithDirectText(prescriptionText)

        XCTAssertTrue(result.isMatch)
        XCTAssertEqual(result.method, .pdf)
    }

    func testPrescriptionFilenameGeneration() throws {
        let prescriptionDetector = DocumentDetector(config: config, documentType: .prescription)

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let date = try XCTUnwrap(dateFormatter.date(from: "2024-12-15"))

        let data = DocumentData(
            documentType: .prescription,
            isMatch: true,
            date: date,
            secondaryField: "Gesine_Kaiser",
            patientName: "Penelope"
        )
        let filename = prescriptionDetector.generateFilename(from: data)

        XCTAssertEqual(filename, "2024-12-15_Rezept_für_Penelope_von_Gesine_Kaiser.pdf")
    }

    func testPrescriptionFilenameGenerationWithoutPatient() throws {
        let prescriptionDetector = DocumentDetector(config: config, documentType: .prescription)

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let date = try XCTUnwrap(dateFormatter.date(from: "2024-12-15"))

        // No patient name - should fallback to simpler pattern
        let data = DocumentData(
            documentType: .prescription,
            isMatch: true,
            date: date,
            secondaryField: "Gesine_Kaiser",
            patientName: nil
        )
        let filename = prescriptionDetector.generateFilename(from: data)

        XCTAssertEqual(filename, "2024-12-15_Rezept_von_Gesine_Kaiser.pdf")
    }

    func testPrescriptionFilenameGenerationWithoutDoctor() throws {
        let prescriptionDetector = DocumentDetector(config: config, documentType: .prescription)

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let date = try XCTUnwrap(dateFormatter.date(from: "2024-12-15"))

        // No doctor name - should fallback to pattern without doctor
        let data = DocumentData(
            documentType: .prescription,
            isMatch: true,
            date: date,
            secondaryField: nil,
            patientName: "Penelope"
        )
        let filename = prescriptionDetector.generateFilename(from: data)

        XCTAssertEqual(filename, "2024-12-15_Rezept_für_Penelope.pdf")
    }

    func testPrescriptionFilenameGenerationWithoutPatientAndDoctor() throws {
        let prescriptionDetector = DocumentDetector(config: config, documentType: .prescription)

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let date = try XCTUnwrap(dateFormatter.date(from: "2024-12-15"))

        // Neither patient nor doctor - minimal pattern
        let data = DocumentData(
            documentType: .prescription,
            isMatch: true,
            date: date,
            secondaryField: nil,
            patientName: nil
        )
        let filename = prescriptionDetector.generateFilename(from: data)

        XCTAssertEqual(filename, "2024-12-15_Rezept.pdf")
    }

    func testDocumentDataForPrescription() {
        let data = DocumentData(
            documentType: .prescription,
            isMatch: true,
            date: Date(),
            secondaryField: "Gesine Kaiser"
        )

        XCTAssertEqual(data.documentType, .prescription)
        XCTAssertTrue(data.isMatch)
        XCTAssertEqual(data.secondaryField, "Gesine Kaiser")
    }
}
