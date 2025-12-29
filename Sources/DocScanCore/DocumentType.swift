import Foundation

/// Supported document types for categorization and data extraction
public enum DocumentType: String, CaseIterable, Codable, Sendable {
    case invoice
    case prescription

    /// Human-readable display name
    public var displayName: String {
        switch self {
        case .invoice:
            return "Invoice"
        case .prescription:
            return "Prescription"
        }
    }

    /// German name for filename generation
    public var germanName: String {
        switch self {
        case .invoice:
            return "Rechnung"
        case .prescription:
            return "Rezept"
        }
    }

    /// VLM prompt for categorization (Phase 1)
    public var vlmPrompt: String {
        switch self {
        case .invoice:
            return "Is this document an INVOICE (Rechnung)? Look for billing information, amounts, invoice numbers. Answer only YES or NO."
        case .prescription:
            return "Is this document a DOCTOR'S PRESCRIPTION (Arzt-Rezept)? Look for medication names, doctor information, patient details. Answer only YES or NO."
        }
    }

    /// Strong indicator keywords (high confidence)
    public var strongKeywords: [String] {
        switch self {
        case .invoice:
            return [
                "rechnungsnummer", "invoice number", "numéro de facture",
                "número de factura", "rechnungsdatum", "invoice date"
            ]
        case .prescription:
            return [
                "rezept", "verordnung", "prescription", "ordonnance",
                "pharmazentralnummer", "pzn", "privatrezept", "kassenrezept"
            ]
        }
    }

    /// Medium indicator keywords (medium confidence)
    public var mediumKeywords: [String] {
        switch self {
        case .invoice:
            return [
                "rechnung", "invoice", "facture", "factura",
                "quittung", "receipt", "beleg"
            ]
        case .prescription:
            return [
                "arzt", "ärztin", "doctor", "dr.med", "dr. med",
                "praxis", "medikament", "medication", "apotheke", "apo",
                "pharmacy", "dosierung", "dosage", "patient", "privat"
            ]
        }
    }

    /// Fields to extract for this document type
    public var extractionFields: [ExtractionField] {
        switch self {
        case .invoice:
            return [.date, .company]
        case .prescription:
            return [.date, .doctor]
        }
    }

    /// Default filename pattern with placeholders
    public var defaultFilenamePattern: String {
        switch self {
        case .invoice:
            return "{date}_Rechnung_{company}.pdf"
        case .prescription:
            return "{date}_Rezept_{doctor}.pdf"
        }
    }

    /// System prompt for TextLLM extraction
    public var extractionSystemPrompt: String {
        switch self {
        case .invoice:
            return "You are an invoice data extraction assistant. Extract information accurately and respond in the exact format requested."
        case .prescription:
            return "You are a medical prescription data extraction assistant. Extract information accurately and respond in the exact format requested."
        }
    }

    /// User prompt for TextLLM extraction
    public func extractionUserPrompt(for text: String) -> String {
        switch self {
        case .invoice:
            return """
            Extract the following information from this invoice text:
            1. Invoice date (Rechnungsdatum): Provide in format YYYY-MM-DD
            2. Invoicing party (company name that issued the invoice)

            IMPORTANT RULES:
            - For date: Look for "Rechnungsdatum", "Invoice Date", or similar. Convert to YYYY-MM-DD format.
            - For company: Extract the company NAME that issued the invoice, NOT the customer name.
            - If you cannot find a value with certainty, respond with "NOT_FOUND" for that field.

            Invoice text:
            ---
            \(text)
            ---

            Respond in this exact format (no other text):
            DATE: YYYY-MM-DD
            COMPANY: Company Name
            """
        case .prescription:
            return """
            Extract the following information from this prescription text:
            1. Prescription date: Provide in format YYYY-MM-DD
            2. Prescribing doctor's name (without title like Dr. or Dr.med.)

            IMPORTANT RULES:
            - For date: Look for the prescription/issue date, NOT pharmacy stamp dates. Convert to YYYY-MM-DD format.
            - For doctor: Extract ONLY the name (e.g., "Gesine Kaiser"), NOT titles like "Dr." or "Dr.med."
            - If multiple doctors are listed, use the one who signed or is marked as prescriber.
            - If you cannot find a value with certainty, respond with "NOT_FOUND" for that field.

            Prescription text:
            ---
            \(text)
            ---

            Respond in this exact format (no other text):
            DATE: YYYY-MM-DD
            DOCTOR: Doctor Name
            """
        }
    }
}

/// Fields that can be extracted from documents
public enum ExtractionField: String, CaseIterable, Codable, Sendable {
    case date
    case company
    case doctor

    /// Placeholder used in filename patterns
    public var placeholder: String {
        return "{\(rawValue)}"
    }
}
