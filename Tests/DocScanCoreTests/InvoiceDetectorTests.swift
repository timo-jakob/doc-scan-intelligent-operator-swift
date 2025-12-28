import XCTest
@testable import DocScanCore

final class InvoiceDetectorTests: XCTestCase {
    var detector: InvoiceDetector!
    var config: Configuration!

    override func setUp() {
        super.setUp()
        config = Configuration.defaultConfiguration
        detector = InvoiceDetector(config: config)
    }

    func testInvoiceDataInitialization() {
        let data = InvoiceData(isInvoice: true, date: Date(), company: "Test Corp")

        XCTAssertTrue(data.isInvoice)
        XCTAssertNotNil(data.date)
        XCTAssertEqual(data.company, "Test Corp")
    }

    func testNotAnInvoice() {
        let data = InvoiceData(isInvoice: false, date: nil, company: nil)

        XCTAssertFalse(data.isInvoice)
        XCTAssertNil(data.date)
        XCTAssertNil(data.company)
    }

    func testGenerateFilenameSuccess() {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let date = dateFormatter.date(from: "2024-12-15")!

        let data = InvoiceData(isInvoice: true, date: date, company: "Acme Corp")
        let filename = detector.generateFilename(from: data)

        XCTAssertEqual(filename, "2024-12-15_Rechnung_Acme Corp.pdf")
    }

    func testGenerateFilenameNotAnInvoice() {
        let data = InvoiceData(isInvoice: false, date: nil, company: nil)
        let filename = detector.generateFilename(from: data)

        XCTAssertNil(filename)
    }

    func testGenerateFilenameMissingData() {
        let data1 = InvoiceData(isInvoice: true, date: Date(), company: nil)
        let filename1 = detector.generateFilename(from: data1)
        XCTAssertNil(filename1)

        let data2 = InvoiceData(isInvoice: true, date: nil, company: "Test")
        let filename2 = detector.generateFilename(from: data2)
        XCTAssertNil(filename2)
    }

    func testCustomFilenamePattern() {
        let customConfig = Configuration(
            output: OutputSettings(filenamePattern: "{company}_{date}_Invoice.pdf")
        )
        let customDetector = InvoiceDetector(config: customConfig)

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let date = dateFormatter.date(from: "2024-12-15")!

        let data = InvoiceData(isInvoice: true, date: date, company: "TestCo")
        let filename = customDetector.generateFilename(from: data)

        XCTAssertEqual(filename, "TestCo_2024-12-15_Invoice.pdf")
    }

    func testCustomDateFormat() {
        let customConfig = Configuration(
            output: OutputSettings(dateFormat: "dd.MM.yyyy")
        )
        let customDetector = InvoiceDetector(config: customConfig)

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let date = dateFormatter.date(from: "2024-12-15")!

        let data = InvoiceData(isInvoice: true, date: date, company: "TestCo")
        let filename = customDetector.generateFilename(from: data)

        XCTAssertEqual(filename, "15.12.2024_Rechnung_TestCo.pdf")
    }
}
