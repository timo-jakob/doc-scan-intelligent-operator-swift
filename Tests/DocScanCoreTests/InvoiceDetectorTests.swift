import AppKit
@testable import DocScanCore
import PDFKit
import XCTest

// MARK: - Document Detector Tests

final class InvoiceDetectorTests: XCTestCase {
    var detector: DocumentDetector!
    var config: Configuration!
    var tempDirectory: URL!
    var mockVLM: MockVLMProvider!

    /// Embedded searchable PDF for testing (also shared with InvoiceDetectorAsyncTests)
    static let sharedSearchablePDFBase64 = """
    JVBERi0xLjQKJcOkw7zDtsOfCjEgMCBvYmoKPDwKL1R5cGUgL0NhdGFsb2cKL1BhZ2VzIDIgMCBS
    Cj4+CmVuZG9iagoKMiAwIG9iago8PAovVHlwZSAvUGFnZXMKL0tpZHMgWzMgMCBSXQovQ291bnQg
    MQo+PgplbmRvYmoKCjMgMCBvYmoKPDwKL1R5cGUgL1BhZ2UKL1BhcmVudCAyIDAgUgovTWVkaWFC
    b3ggWzAgMCA2MTIgNzkyXQovQ29udGVudHMgNCAwIFIKL1Jlc291cmNlcyA8PAovRm9udCA8PAov
    RjEgNSAwIFIKPj4KPj4KPj4KZW5kb2JqCgo0IDAgb2JqCjw8Ci9MZW5ndGggMTIzCj4+CnN0cmVh
    bQpCVAovRjEgMTIgVGYKNTAgNzAwIFRkCihIZWxsbyBXb3JsZCBSZWNobnVuZyBJbnZvaWNlIFRl
    c3QgRG9jdW1lbnQgMTIzNDUgVGhpcyBpcyBhIHRlc3QgUERGIHdpdGggc2VhcmNoYWJsZSB0ZXh0
    KSBUagpFVAplbmRzdHJlYW0KZW5kb2JqCgo1IDAgb2JqCjw8Ci9UeXBlIC9Gb250Ci9TdWJ0eXBl
    IC9UeXBlMQovQmFzZUZvbnQgL0hlbHZldGljYQo+PgplbmRvYmoKCnhyZWYKMCA2CjAwMDAwMDAw
    MDAgNjU1MzUgZiAKMDAwMDAwMDAxNSAwMDAwMCBuIAowMDAwMDAwMDY4IDAwMDAwIG4gCjAwMDAw
    MDAxMjcgMDAwMDAgbiAKMDAwMDAwMDI5NCAwMDAwMCBuIAowMDAwMDAwNDY5IDAwMDAwIG4gCnRy
    YWlsZXIKPDwKL1NpemUgNgovUm9vdCAxIDAgUgo+PgpzdGFydHhyZWYKNTQ5CiUlRU9GCg==
    """

    override func setUp() {
        super.setUp()
        config = Configuration.defaultConfiguration
        mockVLM = MockVLMProvider()
        detector = DocumentDetector(config: config, vlmProvider: mockVLM)
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDirectory)
        mockVLM = nil
        super.tearDown()
    }

    /// Create detector without mock for tests that don't need VLM
    private func createDetectorWithoutMock() -> DocumentDetector {
        DocumentDetector(config: config)
    }

    func createSearchablePDF() throws -> String {
        let pdfPath = tempDirectory.appendingPathComponent("test_invoice.pdf").path
        guard let pdfData = Data(
            base64Encoded: Self.sharedSearchablePDFBase64,
            options: .ignoreUnknownCharacters
        ) else {
            throw NSError(domain: "TestError", code: 1)
        }
        try pdfData.write(to: URL(fileURLWithPath: pdfPath))
        return pdfPath
    }

    func createEmptyPDF() throws -> String {
        let pdfPath = tempDirectory.appendingPathComponent("empty.pdf").path
        var mediaBox = CGRect(x: 0, y: 0, width: 612, height: 792)
        guard let context = CGContext(URL(fileURLWithPath: pdfPath) as CFURL, mediaBox: &mediaBox, nil) else {
            throw NSError(domain: "TestError", code: 1)
        }
        context.beginPage(mediaBox: &mediaBox)
        context.endPage()
        context.closePDF()
        return pdfPath
    }

    func testInvoiceDataInitialization() {
        let data = DocumentData(
            documentType: .invoice,
            isMatch: true,
            date: Date(),
            secondaryField: "Test Corp"
        )

        XCTAssertTrue(data.isMatch)
        XCTAssertNotNil(data.date)
        XCTAssertEqual(data.secondaryField, "Test Corp")
    }

    func testNotAnInvoice() {
        let data = DocumentData(
            documentType: .invoice,
            isMatch: false,
            date: nil,
            secondaryField: nil
        )

        XCTAssertFalse(data.isMatch)
        XCTAssertNil(data.date)
        XCTAssertNil(data.secondaryField)
    }

    func testGenerateFilenameSuccess() throws {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let date = try XCTUnwrap(dateFormatter.date(from: "2024-12-15"))

        let data = DocumentData(
            documentType: .invoice,
            isMatch: true,
            date: date,
            secondaryField: "Acme_Corp"
        )
        let filename = detector.generateFilename(from: data)

        XCTAssertEqual(filename, "2024-12-15_Rechnung_Acme_Corp.pdf")
    }

    func testGenerateFilenameNotAnInvoice() {
        let data = DocumentData(
            documentType: .invoice,
            isMatch: false,
            date: nil,
            secondaryField: nil
        )
        let filename = detector.generateFilename(from: data)

        XCTAssertNil(filename)
    }

    func testGenerateFilenameMissingData() {
        let data1 = DocumentData(
            documentType: .invoice,
            isMatch: true,
            date: Date(),
            secondaryField: nil
        )
        let filename1 = detector.generateFilename(from: data1)
        XCTAssertNil(filename1)

        let data2 = DocumentData(
            documentType: .invoice,
            isMatch: true,
            date: nil,
            secondaryField: "Test"
        )
        let filename2 = detector.generateFilename(from: data2)
        XCTAssertNil(filename2)
    }

    func testCustomFilenamePattern() throws {
        // Note: DocumentDetector uses DocumentType's default pattern, not Configuration
        // This test verifies the invoice default pattern works
        let customConfig = Configuration()
        let customDetector = DocumentDetector(config: customConfig, documentType: .invoice)

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let date = try XCTUnwrap(dateFormatter.date(from: "2024-12-15"))

        let data = DocumentData(
            documentType: .invoice,
            isMatch: true,
            date: date,
            secondaryField: "TestCo"
        )
        let filename = customDetector.generateFilename(from: data)

        XCTAssertEqual(filename, "2024-12-15_Rechnung_TestCo.pdf")
    }

    func testCustomDateFormat() throws {
        let customConfig = Configuration(
            output: OutputSettings(dateFormat: "dd.MM.yyyy")
        )
        let customDetector = DocumentDetector(config: customConfig, documentType: .invoice)

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let date = try XCTUnwrap(dateFormatter.date(from: "2024-12-15"))

        let data = DocumentData(
            documentType: .invoice,
            isMatch: true,
            date: date,
            secondaryField: "TestCo"
        )
        let filename = customDetector.generateFilename(from: data)

        XCTAssertEqual(filename, "15.12.2024_Rechnung_TestCo.pdf")
    }
}

// MARK: - Pre-loaded TextLLM Initializer Tests

extension InvoiceDetectorTests {
    func testDocumentDetectorInitWithPreloadedTextLLM() {
        let textLLM = TextLLMManager(config: config)
        let detectorWithTextLLM = DocumentDetector(
            config: config,
            documentType: .invoice,
            vlmProvider: mockVLM,
            textLLM: textLLM
        )

        XCTAssertEqual(detectorWithTextLLM.documentType, .invoice)
    }

    func testDocumentDetectorInitWithPreloadedTextLLMPrescription() {
        let textLLM = TextLLMManager(config: config)
        let detectorWithTextLLM = DocumentDetector(
            config: config,
            documentType: .prescription,
            vlmProvider: mockVLM,
            textLLM: textLLM
        )

        XCTAssertEqual(detectorWithTextLLM.documentType, .prescription)
    }

    func testDocumentDetectorInitWithPreloadedTextLLMGeneratesFilename() throws {
        let textLLM = TextLLMManager(config: config)
        let detectorWithTextLLM = DocumentDetector(
            config: config,
            documentType: .invoice,
            vlmProvider: mockVLM,
            textLLM: textLLM
        )

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let date = try XCTUnwrap(dateFormatter.date(from: "2025-01-15"))
        let data = DocumentData(
            documentType: .invoice,
            isMatch: true,
            date: date,
            secondaryField: "Test_Corp"
        )
        let filename = detectorWithTextLLM.generateFilename(from: data)
        XCTAssertEqual(filename, "2025-01-15_Rechnung_Test_Corp.pdf")
    }
}
