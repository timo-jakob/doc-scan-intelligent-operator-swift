import Foundation

/// Metadata about how ground truth was generated
public struct GroundTruthMetadata: Codable, Equatable, Sendable {
    /// VLM model used to generate this ground truth
    public var vlmModel: String?

    /// Text LLM model used to generate this ground truth
    public var textModel: String?

    /// When this ground truth was generated
    public var generatedAt: Date?

    /// Whether a human has verified this ground truth
    public var verified: Bool

    public init(
        vlmModel: String? = nil,
        textModel: String? = nil,
        generatedAt: Date? = nil,
        verified: Bool = false
    ) {
        self.vlmModel = vlmModel
        self.textModel = textModel
        self.generatedAt = generatedAt
        self.verified = verified
    }
}

/// Ground truth for a single document, stored as a JSON sidecar file
public struct GroundTruth: Codable, Equatable, Sendable {
    /// Whether this document matches the target document type
    public var isMatch: Bool

    /// The document type this ground truth is for
    public var documentType: DocumentType

    /// Expected date extracted from the document (ISO format: YYYY-MM-DD)
    public var date: String?

    /// Expected secondary field (company for invoices, doctor for prescriptions)
    public var secondaryField: String?

    /// Expected patient name (for prescriptions)
    public var patientName: String?

    /// Metadata about generation
    public var metadata: GroundTruthMetadata

    public init(
        isMatch: Bool,
        documentType: DocumentType,
        date: String? = nil,
        secondaryField: String? = nil,
        patientName: String? = nil,
        metadata: GroundTruthMetadata = GroundTruthMetadata()
    ) {
        self.isMatch = isMatch
        self.documentType = documentType
        self.date = date
        self.secondaryField = secondaryField
        self.patientName = patientName
        self.metadata = metadata
    }

    /// Compute the sidecar JSON path for a given PDF path
    public static func sidecarPath(for pdfPath: String) -> String {
        pdfPath + ".json"
    }

    /// Load ground truth from a JSON sidecar file
    public static func load(from path: String) throws -> GroundTruth {
        let url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: path) else {
            throw DocScanError.fileNotFound(path)
        }
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(GroundTruth.self, from: data)
    }

    /// Save ground truth to a JSON sidecar file (pretty-printed, sorted keys)
    public func save(to path: String) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(self)
        let url = URL(fileURLWithPath: path)
        try data.write(to: url)
    }
}
