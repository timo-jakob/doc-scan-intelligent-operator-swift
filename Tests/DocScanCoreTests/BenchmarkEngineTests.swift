@testable import DocScanCore
import XCTest

final class BenchmarkEngineTests: XCTestCase {
    var engine: BenchmarkEngine!
    var tempDir: URL!

    override func setUp() {
        super.setUp()
        engine = BenchmarkEngine(
            configuration: Configuration(),
            documentType: .invoice,
            verbose: false
        )
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("BenchmarkEngineTests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    // MARK: - Helpers

    private func createMinimalPDF(at url: URL) throws {
        let pdfData = NSMutableData()
        guard let consumer = CGDataConsumer(data: pdfData as CFMutableData),
              let context = CGContext(consumer: consumer, mediaBox: nil, nil)
        else {
            throw DocScanError.pdfConversionFailed("Could not create PDF context")
        }
        var mediaBox = CGRect(x: 0, y: 0, width: 100, height: 100)
        context.beginPage(mediaBox: &mediaBox)
        context.endPage()
        context.closePDF()
        try (pdfData as Data).write(to: url)
    }

    // MARK: - enumeratePDFs

    func testEnumeratePDFsFiltersPDFsAndSorts() throws {
        // Create mixed files
        try createMinimalPDF(at: tempDir.appendingPathComponent("beta.pdf"))
        try createMinimalPDF(at: tempDir.appendingPathComponent("alpha.pdf"))
        try "not a pdf".write(to: tempDir.appendingPathComponent("readme.txt"), atomically: true, encoding: .utf8)
        try "image data".write(to: tempDir.appendingPathComponent("photo.png"), atomically: true, encoding: .utf8)

        let pdfs = try engine.enumeratePDFs(in: tempDir.path)

        XCTAssertEqual(pdfs.count, 2)
        // Should be sorted alphabetically
        XCTAssertTrue(pdfs[0].hasSuffix("alpha.pdf"))
        XCTAssertTrue(pdfs[1].hasSuffix("beta.pdf"))
    }

    func testEnumeratePDFsThrowsForNonExistentDirectory() {
        let badPath = tempDir.appendingPathComponent("nonexistent").path
        XCTAssertThrowsError(try engine.enumeratePDFs(in: badPath)) { error in
            guard let docError = error as? DocScanError else {
                XCTFail("Expected DocScanError, got \(error)")
                return
            }
            if case let .fileNotFound(path) = docError {
                XCTAssertEqual(path, badPath)
            } else {
                XCTFail("Expected fileNotFound error, got \(docError)")
            }
        }
    }

    func testEnumeratePDFsReturnsEmptyForEmptyDirectory() throws {
        let pdfs = try engine.enumeratePDFs(in: tempDir.path)
        XCTAssertEqual(pdfs, [])
    }

    // MARK: - checkExistingSidecars

    func testCheckExistingSidecarsDetectsPresence() throws {
        let posDir = tempDir.appendingPathComponent("positive")
        let negDir = tempDir.appendingPathComponent("negative")
        try FileManager.default.createDirectory(at: posDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: negDir, withIntermediateDirectories: true)

        // Create PDFs
        try createMinimalPDF(at: posDir.appendingPathComponent("a.pdf"))
        try createMinimalPDF(at: posDir.appendingPathComponent("b.pdf"))
        try createMinimalPDF(at: negDir.appendingPathComponent("c.pdf"))

        // Create sidecar for a.pdf only
        let sidecarPath = posDir.appendingPathComponent("a.pdf.json").path
        let groundTruth = GroundTruth(isMatch: true, documentType: .invoice, date: "2025-01-01")
        try groundTruth.save(to: sidecarPath)

        let result = try engine.checkExistingSidecars(
            positiveDir: posDir.path,
            negativeDir: negDir.path
        )

        XCTAssertEqual(result.count, 3)
        // a.pdf has a sidecar
        let aPath = posDir.appendingPathComponent("a.pdf").path
        XCTAssertTrue(result[aPath] ?? false)
        // b.pdf does not
        let bPath = posDir.appendingPathComponent("b.pdf").path
        XCTAssertFalse(result[bPath] ?? true)
        // c.pdf does not
        let cPath = negDir.appendingPathComponent("c.pdf").path
        XCTAssertFalse(result[cPath] ?? true)
    }

    func testCheckExistingSidecarsEmptyDirectories() throws {
        let posDir = tempDir.appendingPathComponent("pos")
        let negDir = tempDir.appendingPathComponent("neg")
        try FileManager.default.createDirectory(at: posDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: negDir, withIntermediateDirectories: true)

        let result = try engine.checkExistingSidecars(
            positiveDir: posDir.path,
            negativeDir: negDir.path
        )
        XCTAssertEqual(result, [:])
    }

    // MARK: - loadGroundTruths

    func testLoadGroundTruthsLoadsAllSidecars() throws {
        // Create PDFs with sidecars
        try createMinimalPDF(at: tempDir.appendingPathComponent("inv1.pdf"))
        try createMinimalPDF(at: tempDir.appendingPathComponent("inv2.pdf"))

        let gt1 = GroundTruth(isMatch: true, documentType: .invoice, date: "2025-01-01", secondaryField: "Acme")
        let gt2 = GroundTruth(isMatch: true, documentType: .invoice, date: "2025-02-15", secondaryField: "Corp")

        let path1 = tempDir.appendingPathComponent("inv1.pdf").path
        let path2 = tempDir.appendingPathComponent("inv2.pdf").path
        try gt1.save(to: GroundTruth.sidecarPath(for: path1))
        try gt2.save(to: GroundTruth.sidecarPath(for: path2))

        let groundTruths = try engine.loadGroundTruths(pdfPaths: [path1, path2])

        XCTAssertEqual(groundTruths.count, 2)
        XCTAssertEqual(groundTruths[path1]?.date, "2025-01-01")
        XCTAssertEqual(groundTruths[path1]?.secondaryField, "Acme")
        XCTAssertEqual(groundTruths[path2]?.date, "2025-02-15")
        XCTAssertEqual(groundTruths[path2]?.secondaryField, "Corp")
    }

    func testLoadGroundTruthsThrowsForMissingSidecar() throws {
        try createMinimalPDF(at: tempDir.appendingPathComponent("missing.pdf"))
        let pdfPath = tempDir.appendingPathComponent("missing.pdf").path

        XCTAssertThrowsError(try engine.loadGroundTruths(pdfPaths: [pdfPath])) { error in
            guard let docError = error as? DocScanError else {
                XCTFail("Expected DocScanError, got \(error)")
                return
            }
            if case let .benchmarkError(message) = docError {
                XCTAssertTrue(message.contains("missing.pdf"), "Error should mention the filename")
            } else {
                XCTFail("Expected benchmarkError, got \(docError)")
            }
        }
    }

    func testLoadGroundTruthsEmptyList() throws {
        let groundTruths = try engine.loadGroundTruths(pdfPaths: [])
        XCTAssertEqual(groundTruths, [:])
    }

    // MARK: - preExtractOCRTexts

    func testPreExtractOCRTextsHandlesMinimalPDFs() async {
        // Minimal PDFs have no text; OCR should return empty or short text
        try? createMinimalPDF(at: tempDir.appendingPathComponent("blank.pdf"))
        let pdfPath = tempDir.appendingPathComponent("blank.pdf").path

        let ocrTexts = await engine.preExtractOCRTexts(
            positivePDFs: [pdfPath],
            negativePDFs: []
        )

        // The blank PDF should either not appear (OCR finds nothing) or have very short text
        if let text = ocrTexts[pdfPath] {
            // If it did extract something, that's fine — just verify it's non-empty
            XCTAssertFalse(text.isEmpty)
        }
        // If missing, blank PDF produced no text — also acceptable
    }

    // MARK: - generateGroundTruths skipExisting

    func testGenerateGroundTruthsSkipExistingPreservesVerifiedSidecars() async throws {
        let pdfPath = tempDir.appendingPathComponent("verified.pdf").path
        try createMinimalPDF(at: tempDir.appendingPathComponent("verified.pdf"))

        // Write a "verified" sidecar that should be preserved
        let existing = GroundTruth(
            isMatch: true,
            documentType: .invoice,
            date: "2025-06-01",
            secondaryField: "Verified_Corp",
            metadata: GroundTruthMetadata(verified: true)
        )
        try existing.save(to: GroundTruth.sidecarPath(for: pdfPath))

        // Generate with skipExisting: true — the verified sidecar should survive
        let results = try await engine.generateGroundTruths(
            positivePDFs: [pdfPath],
            negativePDFs: [],
            ocrTexts: [:],
            skipExisting: true
        )

        let loaded = results[pdfPath]
        XCTAssertEqual(loaded?.date, "2025-06-01")
        XCTAssertEqual(loaded?.secondaryField, "Verified_Corp")
        XCTAssertTrue(loaded?.metadata.verified ?? false, "Verified flag should be preserved")
    }

    func testGenerateGroundTruthsWithoutSkipOverwritesSidecars() async throws {
        let negPath = tempDir.appendingPathComponent("neg.pdf").path
        try createMinimalPDF(at: tempDir.appendingPathComponent("neg.pdf"))

        // Write an existing sidecar with a distinctive field
        let existing = GroundTruth(
            isMatch: false,
            documentType: .invoice,
            metadata: GroundTruthMetadata(vlmModel: "old-model", verified: true)
        )
        try existing.save(to: GroundTruth.sidecarPath(for: negPath))

        // Generate with skipExisting: false — should overwrite
        let results = try await engine.generateGroundTruths(
            positivePDFs: [],
            negativePDFs: [negPath],
            ocrTexts: [:],
            skipExisting: false
        )

        let loaded = results[negPath]
        XCTAssertFalse(loaded?.metadata.verified ?? true, "Overwritten sidecar should not be verified")
    }

    func testPreExtractOCRTextsEmptyInput() async {
        let ocrTexts = await engine.preExtractOCRTexts(
            positivePDFs: [],
            negativePDFs: []
        )
        XCTAssertEqual(ocrTexts, [:])
    }
}
