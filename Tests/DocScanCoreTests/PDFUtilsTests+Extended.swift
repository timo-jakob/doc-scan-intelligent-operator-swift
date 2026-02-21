@testable import DocScanCore
import PDFKit
import XCTest

// MARK: - Validate PDF Tests

extension PDFUtilsTests {
    func testValidatePDFFileNotFound() {
        let nonExistentPath = "/nonexistent/path/file.pdf"

        XCTAssertThrowsError(
            try PDFUtils.validatePDF(at: nonExistentPath)
        ) { error in
            guard let docScanError = error as? DocScanError else {
                XCTFail("Expected DocScanError")
                return
            }
            if case let .fileNotFound(path) = docScanError {
                XCTAssertEqual(path, nonExistentPath)
            } else {
                XCTFail("Expected fileNotFound error")
            }
        }
    }

    func testValidatePDFInvalidFile() throws {
        let tempDir = FileManager.default.temporaryDirectory
        let fakePDFPath = tempDir.appendingPathComponent(
            "fake_\(UUID().uuidString).pdf"
        ).path

        try "This is not a valid PDF content".write(
            toFile: fakePDFPath,
            atomically: true,
            encoding: .utf8
        )
        defer {
            try? FileManager.default.removeItem(atPath: fakePDFPath)
        }

        XCTAssertThrowsError(
            try PDFUtils.validatePDF(at: fakePDFPath)
        ) { error in
            guard let docScanError = error as? DocScanError else {
                XCTFail("Expected DocScanError")
                return
            }
            if case let .invalidPDF(message) = docScanError {
                XCTAssertTrue(message.contains("Unable to open"))
            } else {
                XCTFail("Expected invalidPDF error")
            }
        }
    }

    func testValidatePDFSuccess() throws {
        let pdfPath = try createTestPDF(
            withText: "Valid PDF content for validation test"
        )
        defer { removeTestPDF(at: pdfPath) }

        XCTAssertNoThrow(try PDFUtils.validatePDF(at: pdfPath))
    }

    func testValidatePDFFromRealFile() throws {
        let testPDFPath = "/Users/timo/repositories/"
            + "invoice-examples/BahnCard_Rechnung.pdf"

        guard FileManager.default.fileExists(atPath: testPDFPath) else {
            throw XCTSkip("Test PDF not available")
        }

        XCTAssertNoThrow(
            try PDFUtils.validatePDF(at: testPDFPath)
        )
    }
}

// MARK: - PDF to Image Tests

extension PDFUtilsTests {
    func testPdfToImageSuccess() throws {
        let pdfPath = try createTestPDF(
            withText: "Test content for image conversion"
        )
        defer { removeTestPDF(at: pdfPath) }

        let image = try PDFUtils.pdfToImage(at: pdfPath)

        XCTAssertGreaterThan(image.size.width, 0)
        XCTAssertGreaterThan(image.size.height, 0)
    }

    func testPdfToImageWithCustomDPI() throws {
        let pdfPath = try createTestPDF(
            withText: "Test content for DPI test"
        )
        defer { removeTestPDF(at: pdfPath) }

        let image72 = try PDFUtils.pdfToImage(at: pdfPath, dpi: 72)
        let image150 = try PDFUtils.pdfToImage(
            at: pdfPath, dpi: 150
        )
        let image300 = try PDFUtils.pdfToImage(
            at: pdfPath, dpi: 300
        )

        // Higher DPI should produce larger images
        XCTAssertLessThan(
            image72.size.width, image150.size.width
        )
        XCTAssertLessThan(
            image150.size.width, image300.size.width
        )
    }

    func testPdfToImageWithVerboseMode() throws {
        let pdfPath = try createTestPDF(
            withText: "Test content for verbose mode"
        )
        defer { removeTestPDF(at: pdfPath) }

        let image = try PDFUtils.pdfToImage(
            at: pdfPath, dpi: 150, verbose: true
        )

        XCTAssertGreaterThan(image.size.width, 0)
    }

    func testPdfToImageInvalidPDF() throws {
        let tempDir = FileManager.default.temporaryDirectory
        let fakePDFPath = tempDir.appendingPathComponent(
            "fake_\(UUID().uuidString).pdf"
        ).path

        try "This is not a valid PDF".write(
            toFile: fakePDFPath,
            atomically: true,
            encoding: .utf8
        )
        defer {
            try? FileManager.default.removeItem(atPath: fakePDFPath)
        }

        XCTAssertThrowsError(
            try PDFUtils.pdfToImage(at: fakePDFPath)
        ) { error in
            guard let docScanError = error as? DocScanError else {
                XCTFail("Expected DocScanError")
                return
            }
            if case .pdfConversionFailed = docScanError {
                // Expected
            } else {
                XCTFail(
                    "Expected pdfConversionFailed error, "
                        + "got: \(docScanError)"
                )
            }
        }
    }

    func testPdfToImageFromRealFile() throws {
        let testPDFPath = "/Users/timo/repositories/"
            + "invoice-examples/BahnCard_Rechnung.pdf"

        guard FileManager.default.fileExists(atPath: testPDFPath) else {
            throw XCTSkip("Test PDF not available")
        }

        let image = try PDFUtils.pdfToImage(
            at: testPDFPath, dpi: 150
        )

        XCTAssertGreaterThan(image.size.width, 0)
        XCTAssertGreaterThan(image.size.height, 0)
    }
}

// MARK: - Image to Data Tests

extension PDFUtilsTests {
    func testImageToDataSuccess() throws {
        let pdfPath = try createTestPDF(
            withText: "Test content for image data conversion"
        )
        defer { removeTestPDF(at: pdfPath) }

        let image = try PDFUtils.pdfToImage(at: pdfPath)
        let data = try PDFUtils.imageToData(image)

        XCTAssertGreaterThan(data.count, 0)
        // PNG signature starts with these bytes
        let pngHeader = Data([0x89, 0x50, 0x4E, 0x47])
        XCTAssertEqual(data.prefix(4), pngHeader)
    }

    func testImageToDataFromRealPDF() throws {
        let testPDFPath = "/Users/timo/repositories/"
            + "invoice-examples/BahnCard_Rechnung.pdf"

        guard FileManager.default.fileExists(atPath: testPDFPath) else {
            throw XCTSkip("Test PDF not available")
        }

        let image = try PDFUtils.pdfToImage(at: testPDFPath)
        let data = try PDFUtils.imageToData(image)

        XCTAssertGreaterThan(data.count, 0)
    }
}

// MARK: - Save Image Tests

extension PDFUtilsTests {
    func testSaveImageSuccess() throws {
        let pdfPath = try createTestPDF(
            withText: "Test content for saving image"
        )
        defer { removeTestPDF(at: pdfPath) }

        let image = try PDFUtils.pdfToImage(at: pdfPath)

        let tempDir = FileManager.default.temporaryDirectory
        let outputPath = tempDir.appendingPathComponent(
            "saved_image_\(UUID().uuidString).png"
        ).path
        defer {
            try? FileManager.default.removeItem(atPath: outputPath)
        }

        try PDFUtils.saveImage(image, to: outputPath)

        XCTAssertTrue(
            FileManager.default.fileExists(atPath: outputPath)
        )

        // Verify it's a valid PNG file
        let savedData = try Data(
            contentsOf: URL(fileURLWithPath: outputPath)
        )
        let pngHeader = Data([0x89, 0x50, 0x4E, 0x47])
        XCTAssertEqual(savedData.prefix(4), pngHeader)
    }
}

// MARK: - Edge Cases

extension PDFUtilsTests {
    func testExtractTextReturnsNilForEmptyPDF() {
        let tempDir = FileManager.default.temporaryDirectory
        let pdfPath = tempDir.appendingPathComponent(
            "empty_\(UUID().uuidString).pdf"
        ).path
        let pdfURL = URL(fileURLWithPath: pdfPath)
        defer {
            try? FileManager.default.removeItem(atPath: pdfPath)
        }

        var mediaBox = CGRect(
            x: 0, y: 0, width: 612, height: 792
        )
        guard let context = CGContext(
            pdfURL as CFURL, mediaBox: &mediaBox, nil
        ) else {
            XCTFail("Failed to create PDF context")
            return
        }

        // Create a page with no text content
        context.beginPage(mediaBox: &mediaBox)
        context.setFillColor(NSColor.white.cgColor)
        context.fill(mediaBox)
        context.endPage()
        context.closePDF()

        let result = PDFUtils.extractText(from: pdfPath)
        XCTAssertTrue(
            result == nil || result?.isEmpty == true
        )
    }

    func testHasExtractableTextVerboseModeInsufficientText() throws {
        // Only 2 characters, below minimum of 50
        let testText = "Hi"
        let pdfPath = try createTestPDF(withText: testText)
        defer { removeTestPDF(at: pdfPath) }

        let result = PDFUtils.hasExtractableText(
            at: pdfPath, verbose: true
        )
        XCTAssertFalse(result)
    }
}
