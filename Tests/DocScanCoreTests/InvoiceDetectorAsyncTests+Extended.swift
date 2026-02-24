import AppKit
@testable import DocScanCore
import PDFKit
import XCTest

// MARK: - Extract Data with Mock TextLLM Tests

extension InvoiceDetectorAsyncTests {
    func testExtractDataWithMockTextLLM() async throws {
        // Verify extractData() returns data from the injected TextLLMManager
        let mockTextLLM = MockTextLLMProvider()
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        mockTextLLM.mockDate = dateFormatter.date(from: "2025-06-15")
        mockTextLLM.mockSecondaryField = "Test_Corp"

        let detector = DocumentDetector(
            config: config,
            documentType: .invoice,
            vlmProvider: mockVLM,
            textLLM: mockTextLLM
        )

        let pdfPath = try createSearchablePDF()
        mockVLM.mockResponse = "YES"
        _ = try await detector.categorize(pdfPath: pdfPath)

        let result = try await detector.extractData()

        XCTAssertEqual(result.secondaryField, "Test_Corp")
        XCTAssertNotNil(result.date)
    }

    func testExtractDataVerboseModeInvoice() async throws {
        // Exercises the verbose output inside extractData() for invoice type
        let verboseConfig = Configuration(verbose: true)
        let mockTextLLM = MockTextLLMProvider()
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        mockTextLLM.mockDate = dateFormatter.date(from: "2025-06-15")
        mockTextLLM.mockSecondaryField = "DB_Fernverkehr_AG"

        let detector = DocumentDetector(
            config: verboseConfig,
            documentType: .invoice,
            vlmProvider: mockVLM,
            textLLM: mockTextLLM
        )

        let pdfPath = try createSearchablePDF()
        mockVLM.mockResponse = "YES"
        _ = try await detector.categorize(pdfPath: pdfPath)

        let result = try await detector.extractData()

        XCTAssertEqual(result.secondaryField, "DB_Fernverkehr_AG")
    }

    func testExtractDataVerboseModePrescription() async throws {
        // Exercises the prescription-specific verbose branch in extractData()
        let verboseConfig = Configuration(verbose: true)
        let mockTextLLM = MockTextLLMProvider()
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        mockTextLLM.mockDate = dateFormatter.date(from: "2025-04-08")
        mockTextLLM.mockSecondaryField = "Dr_Mueller"
        mockTextLLM.mockPatientName = "Anna"

        let detector = DocumentDetector(
            config: verboseConfig,
            documentType: .prescription,
            vlmProvider: mockVLM,
            textLLM: mockTextLLM
        )

        let pdfPath = try createSearchablePDF()
        mockVLM.mockResponse = "YES"
        _ = try await detector.categorize(pdfPath: pdfPath)

        let result = try await detector.extractData()

        XCTAssertEqual(result.secondaryField, "Dr_Mueller")
        XCTAssertEqual(result.patientName, "Anna")
    }

    func testExtractDataVerboseModeNilValues() async throws {
        // Exercises verbose output when date and secondary field are nil
        let verboseConfig = Configuration(verbose: true)
        let mockTextLLM = MockTextLLMProvider()

        let detector = DocumentDetector(
            config: verboseConfig,
            documentType: .invoice,
            vlmProvider: mockVLM,
            textLLM: mockTextLLM
        )

        let pdfPath = try createSearchablePDF()
        mockVLM.mockResponse = "YES"
        _ = try await detector.categorize(pdfPath: pdfPath)

        let result = try await detector.extractData()

        XCTAssertNil(result.date)
        XCTAssertNil(result.secondaryField)
    }
}
