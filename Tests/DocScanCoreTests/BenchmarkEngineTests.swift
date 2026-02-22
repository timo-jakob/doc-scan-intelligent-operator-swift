import AppKit
import CoreGraphics
import CoreText
@testable import DocScanCore
import PDFKit
import XCTest

final class BenchmarkEngineTests: XCTestCase {
    var tempDirectory: URL!
    var positiveDir: URL!
    var negativeDir: URL!

    override func setUp() {
        super.setUp()
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        positiveDir = tempDirectory.appendingPathComponent("positive")
        negativeDir = tempDirectory.appendingPathComponent("negative")
        try? FileManager.default.createDirectory(at: positiveDir, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: negativeDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDirectory)
        super.tearDown()
    }

    /// Create a minimal valid PDF file with text content for testing
    private static let defaultPDFText = "Rechnung Nr. 12345\nRechnungsdatum: 27.06.2025\nTest Company GmbH"

    private func createTestPDF(at url: URL, text: String = defaultPDFText) {
        let pdfData = NSMutableData()
        guard let consumer = CGDataConsumer(data: pdfData as CFMutableData) else { return }
        var mediaBox = CGRect(x: 0, y: 0, width: 612, height: 792)
        guard let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else { return }

        context.beginPage(mediaBox: &mediaBox)
        let font = CTFontCreateWithName("Helvetica" as CFString, 12, nil)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: CGColor(red: 0, green: 0, blue: 0, alpha: 1),
        ]
        let attrString = NSAttributedString(string: text, attributes: attrs)
        let line = CTLineCreateWithAttributedString(attrString)
        context.textPosition = CGPoint(x: 72, y: 700)
        CTLineDraw(line, context)
        context.endPage()
        context.closePDF()

        try? pdfData.write(to: url)
    }

    /// Create a text file (non-PDF)
    private func createTextFile(at url: URL) {
        try? "not a pdf".write(to: url, atomically: true, encoding: .utf8)
    }

    // MARK: - PDF Enumeration

    func testEnumeratePDFs() throws {
        createTestPDF(at: positiveDir.appendingPathComponent("a.pdf"))
        createTestPDF(at: positiveDir.appendingPathComponent("b.pdf"))
        createTestPDF(at: positiveDir.appendingPathComponent("c.pdf"))

        let config = Configuration()
        let engine = BenchmarkEngine(configuration: config, documentType: .invoice)
        let pdfs = try engine.enumeratePDFs(in: positiveDir.path)

        XCTAssertEqual(pdfs.count, 3)
        XCTAssertTrue(pdfs[0].hasSuffix("a.pdf"))
        XCTAssertTrue(pdfs[1].hasSuffix("b.pdf"))
        XCTAssertTrue(pdfs[2].hasSuffix("c.pdf"))
    }

    func testEnumeratePDFsFilterNonPDFs() throws {
        createTestPDF(at: positiveDir.appendingPathComponent("doc.pdf"))
        createTextFile(at: positiveDir.appendingPathComponent("readme.txt"))
        createTextFile(at: positiveDir.appendingPathComponent("image.jpg"))

        let config = Configuration()
        let engine = BenchmarkEngine(configuration: config, documentType: .invoice)
        let pdfs = try engine.enumeratePDFs(in: positiveDir.path)

        XCTAssertEqual(pdfs.count, 1)
        XCTAssertTrue(pdfs[0].hasSuffix("doc.pdf"))
    }

    func testEnumerateEmptyDirectory() throws {
        let config = Configuration()
        let engine = BenchmarkEngine(configuration: config, documentType: .invoice)
        let pdfs = try engine.enumeratePDFs(in: positiveDir.path)

        XCTAssertTrue(pdfs.isEmpty)
    }

    func testEnumerateNonExistentDirectory() {
        let config = Configuration()
        let engine = BenchmarkEngine(configuration: config, documentType: .invoice)

        XCTAssertThrowsError(try engine.enumeratePDFs(in: "/non/existent/dir")) { error in
            XCTAssertTrue(error is DocScanError)
        }
    }

    // MARK: - Sidecar Management

    func testCheckExistingSidecarsNone() throws {
        createTestPDF(at: positiveDir.appendingPathComponent("a.pdf"))
        createTestPDF(at: positiveDir.appendingPathComponent("b.pdf"))

        let config = Configuration()
        let engine = BenchmarkEngine(configuration: config, documentType: .invoice)
        let sidecars = try engine.checkExistingSidecars(positiveDir: positiveDir.path, negativeDir: nil)

        XCTAssertEqual(sidecars.count, 2)
        for (_, exists) in sidecars {
            XCTAssertFalse(exists)
        }
    }

    func testCheckExistingSidecarsWithExisting() throws {
        let pdfPath = positiveDir.appendingPathComponent("a.pdf")
        createTestPDF(at: pdfPath)

        // Create a sidecar
        let groundTruth = GroundTruth(isMatch: true, documentType: .invoice, date: "2025-01-01")
        try groundTruth.save(to: pdfPath.path + ".json")

        let config = Configuration()
        let engine = BenchmarkEngine(configuration: config, documentType: .invoice)
        let sidecars = try engine.checkExistingSidecars(positiveDir: positiveDir.path, negativeDir: nil)

        XCTAssertTrue(sidecars[pdfPath.path] ?? false)
    }

    // MARK: - Ground Truth Loading

    func testLoadGroundTruths() throws {
        let pdfPath1 = positiveDir.appendingPathComponent("a.pdf")
        let pdfPath2 = positiveDir.appendingPathComponent("b.pdf")
        createTestPDF(at: pdfPath1)
        createTestPDF(at: pdfPath2)

        let gt1 = GroundTruth(isMatch: true, documentType: .invoice, date: "2025-01-01", secondaryField: "Company_A")
        let gt2 = GroundTruth(isMatch: true, documentType: .invoice, date: "2025-02-02", secondaryField: "Company_B")
        try gt1.save(to: pdfPath1.path + ".json")
        try gt2.save(to: pdfPath2.path + ".json")

        let config = Configuration()
        let engine = BenchmarkEngine(configuration: config, documentType: .invoice)
        let gts = try engine.loadGroundTruths(pdfPaths: [pdfPath1.path, pdfPath2.path])

        XCTAssertEqual(gts.count, 2)
        XCTAssertEqual(gts[pdfPath1.path]?.secondaryField, "Company_A")
        XCTAssertEqual(gts[pdfPath2.path]?.secondaryField, "Company_B")
    }

    func testLoadGroundTruthsMissingSidecar() throws {
        let pdfPath = positiveDir.appendingPathComponent("a.pdf")
        createTestPDF(at: pdfPath)
        // No sidecar created

        let config = Configuration()
        let engine = BenchmarkEngine(configuration: config, documentType: .invoice)

        XCTAssertThrowsError(try engine.loadGroundTruths(pdfPaths: [pdfPath.path])) { error in
            if let docError = error as? DocScanError,
               case let .benchmarkError(msg) = docError {
                XCTAssertTrue(msg.contains("Missing ground truth"))
            } else {
                XCTFail("Expected benchmarkError")
            }
        }
    }

    // MARK: - Memory Check

    func testAvailableMemoryMBReturnsPositive() {
        let memory = BenchmarkEngine.availableMemoryMB()
        XCTAssertGreaterThan(memory, 0)
    }

    // MARK: - Benchmark with Mocks

    func testBenchmarkModelPairAllCorrect() async throws {
        let pdfPath = positiveDir.appendingPathComponent("invoice.pdf")
        createTestPDF(at: pdfPath)

        let groundTruth = GroundTruth(
            isMatch: true,
            documentType: .invoice,
            date: "2025-06-27",
            secondaryField: "Test_Company"
        )

        let factory = MockDocumentDetectorFactory()
        factory.mockVLMResponse = "YES"
        factory.mockDate = DateUtils.parseDate("2025-06-27")
        factory.mockSecondaryField = "Test_Company"

        let config = Configuration()
        let engine = BenchmarkEngine(
            configuration: config,
            documentType: .invoice,
            detectorFactory: factory
        )

        let pair = ModelPair(vlmModelName: config.modelName, textModelName: config.textModelName)
        let result = try await engine.benchmarkModelPair(
            pair,
            pdfPaths: [pdfPath.path],
            groundTruths: [pdfPath.path: groundTruth],
            timeoutSeconds: 30
        )

        XCTAssertFalse(result.isDisqualified)
        XCTAssertEqual(result.metrics.accuracy, 1.0)
    }

    func testBenchmarkModelPairWrongResult() async throws {
        let pdfPath = positiveDir.appendingPathComponent("invoice.pdf")
        createTestPDF(at: pdfPath)

        let groundTruth = GroundTruth(
            isMatch: true,
            documentType: .invoice,
            date: "2025-06-27",
            secondaryField: "Expected_Company"
        )

        let factory = MockDocumentDetectorFactory()
        factory.mockVLMResponse = "YES"
        factory.mockDate = DateUtils.parseDate("2025-06-27")
        factory.mockSecondaryField = "Wrong_Company"

        let config = Configuration()
        let engine = BenchmarkEngine(
            configuration: config,
            documentType: .invoice,
            detectorFactory: factory
        )

        let pair = ModelPair(vlmModelName: config.modelName, textModelName: config.textModelName)
        let result = try await engine.benchmarkModelPair(
            pair,
            pdfPaths: [pdfPath.path],
            groundTruths: [pdfPath.path: groundTruth],
            timeoutSeconds: 30
        )

        XCTAssertEqual(result.metrics.accuracy, 0.0)
    }

    func testBenchmarkWithNegativeDirectory() async throws {
        let posPDF = positiveDir.appendingPathComponent("invoice.pdf")
        let negPDF = negativeDir.appendingPathComponent("not_invoice.pdf")
        createTestPDF(at: posPDF)
        createTestPDF(at: negPDF, text: "Lorem ipsum dolor sit amet")

        let posGT = GroundTruth(isMatch: true, documentType: .invoice, date: "2025-01-01", secondaryField: "Company")
        let negGT = GroundTruth(isMatch: false, documentType: .invoice)

        let factory = MockDocumentDetectorFactory()
        factory.mockVLMResponse = "NO" // Says it's NOT an invoice

        let config = Configuration()
        let engine = BenchmarkEngine(
            configuration: config,
            documentType: .invoice,
            detectorFactory: factory
        )

        let pair = ModelPair(vlmModelName: config.modelName, textModelName: config.textModelName)
        let groundTruths = [posPDF.path: posGT, negPDF.path: negGT]
        let result = try await engine.benchmarkModelPair(
            pair,
            pdfPaths: [posPDF.path, negPDF.path],
            groundTruths: groundTruths,
            timeoutSeconds: 30
        )

        // VLM says NO for both: positive=FN, negative=TN
        XCTAssertEqual(result.metrics.trueNegatives, 1)
        XCTAssertEqual(result.metrics.falseNegatives, 1)
        XCTAssertTrue(result.metrics.hasNegativeSamples)
    }
}
