@testable import DocScanCore
import XCTest

final class GroundTruthTests: XCTestCase {
    var tempDirectory: URL!

    override func setUp() {
        super.setUp()
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(
            at: tempDirectory,
            withIntermediateDirectories: true
        )
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDirectory)
        super.tearDown()
    }

    // MARK: - Sidecar Path

    func testSidecarPathAppendsJson() {
        let path = GroundTruth.sidecarPath(for: "/path/to/invoice.pdf")
        XCTAssertEqual(path, "/path/to/invoice.pdf.json")
    }

    func testSidecarPathWithComplexPath() {
        let path = GroundTruth.sidecarPath(for: "/users/test/documents/scan 2025.pdf")
        XCTAssertEqual(path, "/users/test/documents/scan 2025.pdf.json")
    }

    // MARK: - Encode/Decode Round-Trip

    func testEncodeDecodeRoundTripAllFields() throws {
        let groundTruth = GroundTruth(
            isMatch: true,
            documentType: .invoice,
            date: "2025-06-27",
            secondaryField: "DB_Fernverkehr_AG",
            patientName: nil,
            metadata: GroundTruthMetadata(
                vlmModel: "mlx-community/Qwen2-VL-2B-Instruct-4bit",
                textModel: "mlx-community/Qwen2.5-7B-Instruct-4bit",
                generatedAt: Date(timeIntervalSince1970: 1_750_000_000),
                verified: true
            )
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(groundTruth)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(GroundTruth.self, from: data)

        XCTAssertEqual(groundTruth, decoded)
    }

    func testEncodeDecodeRoundTripOptionalFieldsNil() throws {
        let groundTruth = GroundTruth(
            isMatch: false,
            documentType: .prescription,
            date: nil,
            secondaryField: nil,
            patientName: nil,
            metadata: GroundTruthMetadata()
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(groundTruth)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(GroundTruth.self, from: data)

        XCTAssertEqual(groundTruth, decoded)
        XCTAssertNil(decoded.date)
        XCTAssertNil(decoded.secondaryField)
        XCTAssertNil(decoded.patientName)
    }

    // MARK: - Save and Load

    func testSaveAndLoadRoundTrip() throws {
        let groundTruth = GroundTruth(
            isMatch: true,
            documentType: .invoice,
            date: "2025-01-15",
            secondaryField: "Acme_Corp",
            metadata: GroundTruthMetadata(
                vlmModel: "test-vlm",
                textModel: "test-text",
                verified: false
            )
        )

        let path = tempDirectory.appendingPathComponent("test.pdf.json").path
        try groundTruth.save(to: path)

        let loaded = try GroundTruth.load(from: path)

        XCTAssertEqual(loaded.isMatch, true)
        XCTAssertEqual(loaded.documentType, .invoice)
        XCTAssertEqual(loaded.date, "2025-01-15")
        XCTAssertEqual(loaded.secondaryField, "Acme_Corp")
        XCTAssertEqual(loaded.metadata.vlmModel, "test-vlm")
        XCTAssertEqual(loaded.metadata.textModel, "test-text")
        XCTAssertFalse(loaded.metadata.verified)
    }

    func testSaveProducesPrettyPrintedJSON() throws {
        let groundTruth = GroundTruth(
            isMatch: true,
            documentType: .invoice,
            date: "2025-06-27",
            secondaryField: "Test_Company"
        )

        let path = tempDirectory.appendingPathComponent("pretty.pdf.json").path
        try groundTruth.save(to: path)

        let content = try String(contentsOfFile: path, encoding: .utf8)
        // Pretty-printed JSON should contain newlines and indentation
        XCTAssertTrue(content.contains("\n"))
        XCTAssertTrue(content.contains("  "))
        // Sorted keys: "date" should come before "isMatch"
        let dateRange = content.range(of: "\"date\"")
        let isMatchRange = content.range(of: "\"isMatch\"")
        XCTAssertNotNil(dateRange)
        XCTAssertNotNil(isMatchRange)
        if let dateR = dateRange, let isMatchR = isMatchRange {
            XCTAssertTrue(dateR.lowerBound < isMatchR.lowerBound, "Keys should be sorted: date before isMatch")
        }
    }

    // MARK: - Error Cases

    func testLoadFromNonExistentPathThrows() {
        let path = "/non/existent/path.pdf.json"
        XCTAssertThrowsError(try GroundTruth.load(from: path)) { error in
            guard let docError = error as? DocScanError else {
                XCTFail("Expected DocScanError, got \(error)")
                return
            }
            if case let .fileNotFound(errorPath) = docError {
                XCTAssertEqual(errorPath, path)
            } else {
                XCTFail("Expected fileNotFound error")
            }
        }
    }

    func testLoadFromMalformedJSONThrows() throws {
        let path = tempDirectory.appendingPathComponent("bad.pdf.json").path
        try "{ not valid json }}}".write(toFile: path, atomically: true, encoding: .utf8)

        XCTAssertThrowsError(try GroundTruth.load(from: path)) { error in
            XCTAssertTrue(error is DecodingError, "Expected DecodingError, got \(error)")
        }
    }

    // MARK: - Metadata Defaults

    func testMetadataVerifiedDefaultsFalse() {
        let metadata = GroundTruthMetadata()
        XCTAssertFalse(metadata.verified)
    }

    func testFreshGroundTruthMetadataVerifiedIsFalse() {
        let groundTruth = GroundTruth(isMatch: true, documentType: .invoice)
        XCTAssertFalse(groundTruth.metadata.verified)
    }

    // MARK: - Equatable

    func testEquatableConformance() {
        let gt1 = GroundTruth(
            isMatch: true,
            documentType: .invoice,
            date: "2025-01-01",
            secondaryField: "Company"
        )
        let gt2 = GroundTruth(
            isMatch: true,
            documentType: .invoice,
            date: "2025-01-01",
            secondaryField: "Company"
        )
        let gt3 = GroundTruth(
            isMatch: false,
            documentType: .invoice,
            date: "2025-01-01",
            secondaryField: "Company"
        )

        XCTAssertEqual(gt1, gt2)
        XCTAssertNotEqual(gt1, gt3)
    }

    func testEquatableDifferentDocumentType() {
        let gt1 = GroundTruth(isMatch: true, documentType: .invoice)
        let gt2 = GroundTruth(isMatch: true, documentType: .prescription)
        XCTAssertNotEqual(gt1, gt2)
    }

    // MARK: - Prescription Ground Truth

    func testPrescriptionGroundTruthWithPatientName() throws {
        let groundTruth = GroundTruth(
            isMatch: true,
            documentType: .prescription,
            date: "2025-04-08",
            secondaryField: "Gesine_Kaiser",
            patientName: "Penelope"
        )

        let path = tempDirectory.appendingPathComponent("rx.pdf.json").path
        try groundTruth.save(to: path)
        let loaded = try GroundTruth.load(from: path)

        XCTAssertEqual(loaded.documentType, .prescription)
        XCTAssertEqual(loaded.patientName, "Penelope")
        XCTAssertEqual(loaded.secondaryField, "Gesine_Kaiser")
    }
}
