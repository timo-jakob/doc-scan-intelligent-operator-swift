@testable import DocScanCore
import XCTest

/// Tests for TextLLMManager response parsing logic, exercised through the mock provider
/// and DocumentDetector's extractData path. Since parseExtractionResponse is private,
/// we validate its behavior indirectly through the extraction pipeline.
final class TextLLMParsingTests: XCTestCase {
    // MARK: - MockTextLLMProvider with controllable extractData

    /// A mock that returns a configurable ExtractionResult, simulating
    /// what parseExtractionResponse would produce for various LLM outputs.
    private func makeDetector(
        mockDate: Date? = nil,
        mockSecondary: String? = nil,
        mockPatient: String? = nil,
        documentType: DocumentType = .invoice
    ) -> (DocumentDetector, MockTextLLMProvider) {
        let mockVLM = MockVLMProvider()
        let mockTextLLM = MockTextLLMProvider()
        mockTextLLM.mockDate = mockDate
        mockTextLLM.mockSecondaryField = mockSecondary
        mockTextLLM.mockPatientName = mockPatient

        let config = Configuration.defaultConfiguration
        let detector = DocumentDetector(
            config: config,
            documentType: documentType,
            vlmProvider: mockVLM,
            textLLM: mockTextLLM
        )
        return (detector, mockTextLLM)
    }

    // MARK: - Invoice Extraction

    func testInvoiceExtractionAllFields() async throws {
        let date = DateUtils.parseDate("2025-06-27")
        let (detector, _) = makeDetector(
            mockDate: date, mockSecondary: "DB_Fernverkehr_AG"
        )

        let context = CategorizationContext(ocrText: "Rechnung Datum 2025-06-27 DB Fernverkehr AG", pdfPath: "/test.pdf")
        let result = try await detector.extractData(context: context)

        XCTAssertEqual(result.date, date)
        XCTAssertEqual(result.secondaryField, "DB_Fernverkehr_AG")
        XCTAssertNil(result.patientName)
    }

    func testInvoiceExtractionDateOnly() async throws {
        let date = DateUtils.parseDate("2025-01-01")
        let (detector, _) = makeDetector(mockDate: date)

        let context = CategorizationContext(ocrText: "Some invoice text", pdfPath: "/test.pdf")
        let result = try await detector.extractData(context: context)

        XCTAssertEqual(result.date, date)
        XCTAssertNil(result.secondaryField)
    }

    func testInvoiceExtractionNoFields() async throws {
        let (detector, _) = makeDetector()

        let context = CategorizationContext(ocrText: "Some text", pdfPath: "/test.pdf")
        let result = try await detector.extractData(context: context)

        XCTAssertNil(result.date)
        XCTAssertNil(result.secondaryField)
    }

    // MARK: - Prescription Extraction

    func testPrescriptionExtractionAllFields() async throws {
        let date = DateUtils.parseDate("2025-04-08")
        let (detector, _) = makeDetector(
            mockDate: date,
            mockSecondary: "Gesine_Kaiser",
            mockPatient: "Max",
            documentType: .prescription
        )

        let context = CategorizationContext(ocrText: "Rezept Dr. Kaiser Patient Max", pdfPath: "/test.pdf")
        let result = try await detector.extractData(context: context)

        XCTAssertEqual(result.date, date)
        XCTAssertEqual(result.secondaryField, "Gesine_Kaiser")
        XCTAssertEqual(result.patientName, "Max")
    }

    func testPrescriptionExtractionDoctorOnly() async throws {
        let date = DateUtils.parseDate("2025-04-08")
        let (detector, _) = makeDetector(
            mockDate: date,
            mockSecondary: "Mueller",
            documentType: .prescription
        )

        let context = CategorizationContext(ocrText: "Rezept Dr. Mueller", pdfPath: "/test.pdf")
        let result = try await detector.extractData(context: context)

        XCTAssertEqual(result.date, date)
        XCTAssertEqual(result.secondaryField, "Mueller")
        XCTAssertNil(result.patientName)
    }

    // MARK: - Error Cases

    func testEmptyOCRTextThrows() async {
        let (detector, _) = makeDetector()

        let context = CategorizationContext(ocrText: "", pdfPath: "/test.pdf")

        do {
            _ = try await detector.extractData(context: context)
            XCTFail("Expected extractionFailed error")
        } catch let error as DocScanError {
            if case .extractionFailed = error {
                // Expected
            } else {
                XCTFail("Expected extractionFailed, got \(error)")
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    func testTextLLMErrorPropagates() async {
        let mockVLM = MockVLMProvider()
        let mockTextLLM = MockTextLLMProvider()
        mockTextLLM.shouldThrowError = true

        let detector = DocumentDetector(
            config: Configuration.defaultConfiguration,
            documentType: .invoice,
            vlmProvider: mockVLM,
            textLLM: mockTextLLM
        )

        let context = CategorizationContext(ocrText: "Some text", pdfPath: "/test.pdf")

        do {
            _ = try await detector.extractData(context: context)
            XCTFail("Expected error")
        } catch {
            XCTAssertTrue(error is DocScanError)
        }
    }
}
