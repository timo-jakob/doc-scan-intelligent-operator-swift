import Foundation

/// Supported document types for categorization and data extraction
public enum DocumentType: String, CaseIterable, Codable, Sendable {
    case invoice
    case prescription

    /// Human-readable display name
    public var displayName: String {
        switch self {
        case .invoice:
            "Invoice"
        case .prescription:
            "Prescription"
        }
    }

    /// German name for filename generation
    public var germanName: String {
        switch self {
        case .invoice:
            "Rechnung"
        case .prescription:
            "Rezept"
        }
    }

    /// VLM prompt for categorization (Phase 1)
    public var vlmPrompt: String {
        switch self {
        case .invoice:
            """
            Classify this document. Is it an INVOICE (Rechnung)?

            An invoice typically shows:
            - A company letterhead or logo
            - An invoice number (Rechnungsnummer)
            - Line items with prices and a total amount due
            - Payment terms or bank details (IBAN)

            This is NOT an invoice if it is a receipt, delivery note, bank statement, letter, or prescription.

            Answer with exactly one word: YES or NO
            """
        case .prescription:
            """
            Classify this document. Is it a DOCTOR'S PRESCRIPTION (Arzt-Rezept)?

            A prescription typically shows:
            - A doctor's name and practice address (Praxis)
            - Patient name and insurance details
            - Medication names with dosage instructions
            - A PZN (Pharmazentralnummer) or Rp. marking

            This is NOT a prescription if it is an invoice, lab report, referral letter, or insurance form.

            Answer with exactly one word: YES or NO
            """
        }
    }

    /// Text-based LLM prompt for categorization of OCR text (used in TextLLM benchmarking)
    public var textCategorizationPrompt: String {
        switch self {
        case .invoice:
            """
            Based on the following document text, classify it. Is it an INVOICE (Rechnung)?

            An invoice typically contains:
            - An invoice number (Rechnungsnummer)
            - Line items with prices and a total amount due
            - Payment terms or bank details (IBAN)

            This is NOT an invoice if it is a receipt, delivery note, bank statement, letter, or prescription.

            Answer with exactly one word: YES or NO
            """
        case .prescription:
            """
            Based on the following document text, classify it. Is it a DOCTOR'S PRESCRIPTION (Arzt-Rezept)?

            A prescription typically contains:
            - A doctor's name and practice address
            - Patient name and insurance details
            - Medication names with dosage instructions
            - A PZN (Pharmazentralnummer)

            This is NOT a prescription if it is an invoice, lab report, referral letter, or insurance form.

            Answer with exactly one word: YES or NO
            """
        }
    }

    /// Strong indicator keywords (high confidence)
    public var strongKeywords: [String] {
        switch self {
        case .invoice:
            [
                "rechnungsnummer", "invoice number", "numéro de facture",
                "número de factura", "rechnungsdatum", "invoice date",
            ]
        case .prescription:
            [
                "rezept", "verordnung", "prescription", "ordonnance",
                "pharmazentralnummer", "pzn", "privatrezept", "kassenrezept",
            ]
        }
    }

    /// Medium indicator keywords (medium confidence)
    public var mediumKeywords: [String] {
        switch self {
        case .invoice:
            [
                "rechnung", "invoice", "facture", "factura",
                "quittung", "receipt", "beleg",
            ]
        case .prescription:
            [
                "arzt", "ärztin", "doctor", "dr.med", "dr. med",
                "praxis", "gemeinschaftspraxis", "medikament", "medication",
                "apotheke", "apo", "pharmacy", "dosierung", "dosage",
                "patient", "privat",
            ]
        }
    }

    /// Fields to extract for this document type
    public var extractionFields: [ExtractionField] {
        switch self {
        case .invoice:
            [.date, .company]
        case .prescription:
            [.date, .doctor, .patient]
        }
    }

    /// Default filename pattern with placeholders
    public var defaultFilenamePattern: String {
        switch self {
        case .invoice:
            "{date}_Rechnung_{company}.pdf"
        case .prescription:
            "{date}_Rezept_für_{patient}_von_{doctor}.pdf"
        }
    }

    /// System prompt for TextLLM extraction
    public var extractionSystemPrompt: String {
        switch self {
        case .invoice:
            "You are an invoice data extraction assistant. " +
                "Extract information accurately and respond in the exact format requested."
        case .prescription:
            "You are a medical prescription data extraction assistant. " +
                "Extract information accurately and respond in the exact format requested."
        }
    }

    /// User prompt for TextLLM extraction
    public func extractionUserPrompt(for text: String) -> String {
        switch self {
        case .invoice:
            Self.invoiceExtractionPrompt(for: text)
        case .prescription:
            Self.prescriptionExtractionPrompt(for: text)
        }
    }

    private static func invoiceExtractionPrompt(for text: String) -> String {
        """
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
    }

    private static func prescriptionExtractionPrompt(for text: String) -> String {
        """
        Extract the following information from this German prescription text:

        1. Patient's FIRST NAME:
           - Look for the top-left address block (standard German letter format)
           - Line 1 = Last name, Line 2 = First name
           - Extract ONLY the first name (e.g., "Penelope")

        2. Prescription date:
           - Look for the prescription/issue date (format like 08.04.25)
           - NOT the birth date, NOT pharmacy stamp dates
           - Convert to YYYY-MM-DD format

        3. Doctor's name:
           - Look for name under "Gemeinschaftspraxis" or "Praxis" header
           - Extract name WITHOUT titles (Dr., Dr.med., Prof., etc.)
           - Just the name (e.g., "Gesine Kaiser")

        IMPORTANT:
        - If you cannot find a value with certainty, respond with "NOT_FOUND"
        - The address block is at top-left, insurance header is at top (ignore it)
        - Birth dates are in format DD.MM.YY and appear near the patient name - ignore these

        Prescription text:
        ---
        \(text)
        ---

        Respond in this exact format (no other text):
        PATIENT: First Name Only
        DATE: YYYY-MM-DD
        DOCTOR: Doctor Name
        """
    }
}

/// Fields that can be extracted from documents
public enum ExtractionField: String, CaseIterable, Codable, Sendable {
    case date
    case company
    case doctor
    case patient

    /// Placeholder used in filename patterns
    public var placeholder: String {
        "{\(rawValue)}"
    }
}
