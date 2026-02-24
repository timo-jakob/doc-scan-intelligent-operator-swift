import Foundation

// MARK: - Confidence Level

/// Confidence level for categorization results
public enum ConfidenceLevel: String, Sendable, Codable {
    case high
    case medium
    case low
}

// MARK: - Extraction Results (Phase 2: OCR+TextLLM only)

/// Result of data extraction (OCR+TextLLM only)
/// Contains date and a secondary field (company for invoices, doctor for prescriptions)
public struct ExtractionResult: Sendable {
    public let date: Date?
    public let secondaryField: String? // company, doctor, etc. depending on document type
    public let patientName: String? // patient first name (for prescriptions)

    public init(date: Date?, secondaryField: String?, patientName: String? = nil) {
        self.date = date
        self.secondaryField = secondaryField
        self.patientName = patientName
    }
}

// MARK: - Final Document Data

/// Final result combining categorization and extraction
public struct DocumentData: Sendable {
    public let documentType: DocumentType
    public let isMatch: Bool // Whether document matches the target type
    public let date: Date?
    public let secondaryField: String? // company, doctor, etc.
    public let patientName: String? // patient first name (for prescriptions)
    public let categorization: CategorizationVerification?

    public init(
        documentType: DocumentType,
        isMatch: Bool,
        date: Date?,
        secondaryField: String?,
        patientName: String? = nil,
        categorization: CategorizationVerification? = nil
    ) {
        self.documentType = documentType
        self.isMatch = isMatch
        self.date = date
        self.secondaryField = secondaryField
        self.patientName = patientName
        self.categorization = categorization
    }
}
