import XCTest
@testable import DocScanCore

final class DocumentTypeTests: XCTestCase {

    // MARK: - Display Name Tests

    func testInvoiceDisplayName() {
        XCTAssertEqual(DocumentType.invoice.displayName, "Invoice")
    }

    func testPrescriptionDisplayName() {
        XCTAssertEqual(DocumentType.prescription.displayName, "Prescription")
    }

    // MARK: - German Name Tests

    func testInvoiceGermanName() {
        XCTAssertEqual(DocumentType.invoice.germanName, "Rechnung")
    }

    func testPrescriptionGermanName() {
        XCTAssertEqual(DocumentType.prescription.germanName, "Rezept")
    }

    // MARK: - VLM Prompt Tests

    func testInvoiceVLMPrompt() {
        let prompt = DocumentType.invoice.vlmPrompt
        XCTAssertTrue(prompt.contains("INVOICE"))
        XCTAssertTrue(prompt.contains("Rechnung"))
        XCTAssertTrue(prompt.contains("YES or NO"))
    }

    func testPrescriptionVLMPrompt() {
        let prompt = DocumentType.prescription.vlmPrompt
        XCTAssertTrue(prompt.contains("PRESCRIPTION"))
        XCTAssertTrue(prompt.contains("Arzt-Rezept"))
        XCTAssertTrue(prompt.contains("YES or NO"))
    }

    // MARK: - Strong Keywords Tests

    func testInvoiceStrongKeywords() {
        let keywords = DocumentType.invoice.strongKeywords
        XCTAssertTrue(keywords.contains("rechnungsnummer"))
        XCTAssertTrue(keywords.contains("invoice number"))
        XCTAssertTrue(keywords.contains("rechnungsdatum"))
    }

    func testPrescriptionStrongKeywords() {
        let keywords = DocumentType.prescription.strongKeywords
        XCTAssertTrue(keywords.contains("rezept"))
        XCTAssertTrue(keywords.contains("verordnung"))
        XCTAssertTrue(keywords.contains("pzn"))
    }

    // MARK: - Medium Keywords Tests

    func testInvoiceMediumKeywords() {
        let keywords = DocumentType.invoice.mediumKeywords
        XCTAssertTrue(keywords.contains("rechnung"))
        XCTAssertTrue(keywords.contains("invoice"))
        XCTAssertTrue(keywords.contains("quittung"))
    }

    func testPrescriptionMediumKeywords() {
        let keywords = DocumentType.prescription.mediumKeywords
        XCTAssertTrue(keywords.contains("arzt"))
        XCTAssertTrue(keywords.contains("praxis"))
        XCTAssertTrue(keywords.contains("medikament"))
        XCTAssertTrue(keywords.contains("apotheke"))
    }

    // MARK: - Extraction Fields Tests

    func testInvoiceExtractionFields() {
        let fields = DocumentType.invoice.extractionFields
        XCTAssertEqual(fields.count, 2)
        XCTAssertTrue(fields.contains(.date))
        XCTAssertTrue(fields.contains(.company))
    }

    func testPrescriptionExtractionFields() {
        let fields = DocumentType.prescription.extractionFields
        XCTAssertEqual(fields.count, 3)
        XCTAssertTrue(fields.contains(.date))
        XCTAssertTrue(fields.contains(.doctor))
        XCTAssertTrue(fields.contains(.patient))
    }

    // MARK: - Default Filename Pattern Tests

    func testInvoiceDefaultFilenamePattern() {
        let pattern = DocumentType.invoice.defaultFilenamePattern
        XCTAssertEqual(pattern, "{date}_Rechnung_{company}.pdf")
    }

    func testPrescriptionDefaultFilenamePattern() {
        let pattern = DocumentType.prescription.defaultFilenamePattern
        XCTAssertEqual(pattern, "{date}_Rezept_für_{patient}_von_{doctor}.pdf")
    }

    // MARK: - Extraction System Prompt Tests

    func testInvoiceExtractionSystemPrompt() {
        let prompt = DocumentType.invoice.extractionSystemPrompt
        XCTAssertTrue(prompt.contains("invoice"))
        XCTAssertTrue(prompt.contains("extraction"))
    }

    func testPrescriptionExtractionSystemPrompt() {
        let prompt = DocumentType.prescription.extractionSystemPrompt
        XCTAssertTrue(prompt.contains("prescription"))
        XCTAssertTrue(prompt.contains("extraction"))
    }

    // MARK: - Extraction User Prompt Tests

    func testInvoiceExtractionUserPrompt() {
        let testText = "Sample invoice text"
        let prompt = DocumentType.invoice.extractionUserPrompt(for: testText)

        XCTAssertTrue(prompt.contains("Invoice date"))
        XCTAssertTrue(prompt.contains("Rechnungsdatum"))
        XCTAssertTrue(prompt.contains("YYYY-MM-DD"))
        XCTAssertTrue(prompt.contains("company"))
        XCTAssertTrue(prompt.contains(testText))
        XCTAssertTrue(prompt.contains("DATE:"))
        XCTAssertTrue(prompt.contains("COMPANY:"))
    }

    func testPrescriptionExtractionUserPrompt() {
        let testText = "Sample prescription text"
        let prompt = DocumentType.prescription.extractionUserPrompt(for: testText)

        XCTAssertTrue(prompt.contains("Prescription date"))
        XCTAssertTrue(prompt.contains("Doctor"))
        XCTAssertTrue(prompt.contains("YYYY-MM-DD"))
        XCTAssertTrue(prompt.contains(testText))
        XCTAssertTrue(prompt.contains("DATE:"))
        XCTAssertTrue(prompt.contains("DOCTOR:"))
        XCTAssertTrue(prompt.contains("PATIENT:"))
        // Check for German format knowledge
        XCTAssertTrue(prompt.contains("Gemeinschaftspraxis") || prompt.contains("Praxis"))
        XCTAssertTrue(prompt.contains("top-left address"))
    }

    // MARK: - CaseIterable Tests

    func testAllCases() {
        let allCases = DocumentType.allCases
        XCTAssertEqual(allCases.count, 2)
        XCTAssertTrue(allCases.contains(.invoice))
        XCTAssertTrue(allCases.contains(.prescription))
    }

    // MARK: - Codable Tests

    func testDocumentTypeCodable() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        // Test invoice encoding/decoding
        let invoiceData = try encoder.encode(DocumentType.invoice)
        let decodedInvoice = try decoder.decode(DocumentType.self, from: invoiceData)
        XCTAssertEqual(decodedInvoice, .invoice)

        // Test prescription encoding/decoding
        let prescriptionData = try encoder.encode(DocumentType.prescription)
        let decodedPrescription = try decoder.decode(DocumentType.self, from: prescriptionData)
        XCTAssertEqual(decodedPrescription, .prescription)
    }

    // MARK: - ExtractionField Tests

    func testExtractionFieldPlaceholder() {
        XCTAssertEqual(ExtractionField.date.placeholder, "{date}")
        XCTAssertEqual(ExtractionField.company.placeholder, "{company}")
        XCTAssertEqual(ExtractionField.doctor.placeholder, "{doctor}")
        XCTAssertEqual(ExtractionField.patient.placeholder, "{patient}")
    }

    func testExtractionFieldRawValue() {
        XCTAssertEqual(ExtractionField.date.rawValue, "date")
        XCTAssertEqual(ExtractionField.company.rawValue, "company")
        XCTAssertEqual(ExtractionField.doctor.rawValue, "doctor")
        XCTAssertEqual(ExtractionField.patient.rawValue, "patient")
    }

    func testExtractionFieldAllCases() {
        let allCases = ExtractionField.allCases
        XCTAssertEqual(allCases.count, 4)
        XCTAssertTrue(allCases.contains(.date))
        XCTAssertTrue(allCases.contains(.company))
        XCTAssertTrue(allCases.contains(.doctor))
        XCTAssertTrue(allCases.contains(.patient))
    }

    func testExtractionFieldCodable() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        for field in ExtractionField.allCases {
            let data = try encoder.encode(field)
            let decoded = try decoder.decode(ExtractionField.self, from: data)
            XCTAssertEqual(decoded, field)
        }
    }
}
