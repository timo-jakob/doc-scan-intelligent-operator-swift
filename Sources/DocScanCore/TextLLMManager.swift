import Foundation
import MLX
import MLXLLM
import MLXLMCommon

/// Manages text-only LLM for analyzing OCR-extracted text using mlx-swift-lm
open class TextLLMManager {
    private let config: Configuration

    /// Default text-only model for analyzing OCR results (Qwen2.5-7B optimized for Apple Silicon)
    private let defaultTextModel = "mlx-community/Qwen2.5-7B-Instruct-4bit"

    /// Model container (lazy loaded)
    private var modelContainer: ModelContainer?

    /// The model identifier used for text LLM inference
    public var modelName: String {
        defaultTextModel
    }

    public init(config: Configuration) {
        self.config = config
    }

    /// Preload the text LLM model so it is ready before processing begins.
    /// Calls progressHandler with fractions 0.0–1.0 only when a download is required.
    /// If the model is already cached locally the handler is never called.
    public func preload(progressHandler: @escaping (Double) -> Void) async throws {
        guard modelContainer == nil else { return }

        modelContainer = try await LLMModelFactory.shared.loadContainer(
            configuration: .init(id: defaultTextModel)
        ) { progress in
            progressHandler(progress.fractionCompleted)
        }
    }

    /// Analyze OCR text using Text-LLM to extract invoice data
    public func analyzeInvoiceText(_ text: String) async throws -> (isInvoice: Bool, date: Date?, company: String?) {
        if config.verbose {
            print("Text-LLM: Analyzing OCR text...")
        }

        // First, check if it's an invoice using keyword detection
        let isInvoice = detectInvoice(from: text)

        guard isInvoice else {
            if config.verbose {
                print("Text-LLM: Not an invoice")
            }
            return (false, nil, nil)
        }

        // Extract date and company using LLM
        let (date, company) = try await extractInvoiceData(from: text)

        if config.verbose {
            print("Text-LLM Results:")
            print("  Is Invoice: \(isInvoice)")
            print("  Date: \(date?.description ?? "nil")")
            print("  Company: \(company ?? "nil")")
        }

        return (isInvoice, date, company)
    }

    /// Detect if text represents an invoice using keyword detection
    private func detectInvoice(from text: String) -> Bool {
        if config.verbose {
            print("Text-LLM: Checking if text contains invoice...")
        }

        // Use shared keyword detection from OCREngine
        let (isInvoice, confidence, reason) = OCREngine.detectInvoiceKeywords(from: text)

        if config.verbose {
            print("Text-LLM: Keyword detection result: \(isInvoice) (confidence: \(confidence))")
            if let reason {
                print("  - \(reason)")
            }
        }

        return isInvoice
    }

    /// Extract date and company from text using LLM (public API for Phase 2)
    /// Legacy method - delegates to generic extractData
    public func extractDateAndCompany(from text: String) async throws -> (Date?, String?) {
        let result = try await extractData(for: .invoice, from: text)
        return (result.date, result.secondaryField)
    }

    /// Generic data extraction for any document type
    /// Returns extracted date, secondary field (company/doctor), and optional patient name
    open func extractData(
        for documentType: DocumentType,
        from text: String
    ) async throws -> (date: Date?, secondaryField: String?, patientName: String?) {
        let systemPrompt = documentType.extractionSystemPrompt
        let userPrompt = documentType.extractionUserPrompt(for: text)

        let response = try await generate(
            systemPrompt: systemPrompt,
            userPrompt: userPrompt,
            maxTokens: config.maxTokens
        )

        // Parse response based on document type
        let lines = response.components(separatedBy: .newlines)
        var date: Date?
        var secondaryField: String?
        var patientName: String?

        // Determine secondary field prefix based on document type
        let secondaryPrefix = switch documentType {
        case .invoice:
            "COMPANY:"
        case .prescription:
            "DOCTOR:"
        }

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("DATE:") {
                let dateString = trimmed
                    .replacingOccurrences(of: "DATE:", with: "")
                    .trimmingCharacters(in: .whitespaces)

                if dateString != "UNKNOWN", dateString != "NOT_FOUND" {
                    date = parseDate(dateString)
                }
            } else if trimmed.hasPrefix(secondaryPrefix) {
                let fieldValue = trimmed
                    .replacingOccurrences(of: secondaryPrefix, with: "")
                    .trimmingCharacters(in: .whitespaces)

                if fieldValue != "UNKNOWN", fieldValue != "NOT_FOUND" {
                    secondaryField = sanitizeFieldValue(fieldValue, for: documentType)
                }
            } else if trimmed.hasPrefix("PATIENT:"), documentType == .prescription {
                let patientValue = trimmed
                    .replacingOccurrences(of: "PATIENT:", with: "")
                    .trimmingCharacters(in: .whitespaces)

                if patientValue != "UNKNOWN", patientValue != "NOT_FOUND" {
                    patientName = StringUtils.sanitizePatientName(patientValue)
                }
            }
        }

        // Fallback: If LLM didn't find a date, try regex-based extraction
        if date == nil {
            if config.verbose {
                print("Text-LLM: Date not found by LLM, trying regex fallback...")
            }
            date = extractDateWithRegex(from: text)
            if config.verbose, date != nil {
                print("Text-LLM: Regex fallback found date: \(DateUtils.formatDate(date!))")
            }
        }

        return (date, secondaryField, patientName)
    }

    /// Sanitize field value based on document type
    private func sanitizeFieldValue(_ value: String, for documentType: DocumentType) -> String {
        switch documentType {
        case .invoice:
            StringUtils.sanitizeCompanyName(value)
        case .prescription:
            StringUtils.sanitizeDoctorName(value)
        }
    }

    /// Extract invoice date and company from text using LLM with regex fallback
    private func extractInvoiceData(from text: String) async throws -> (Date?, String?) {
        let systemPrompt = """
        You are an invoice data extraction assistant. Extract information accurately and respond in the exact format requested.
        """

        let userPrompt = """
        Extract the following information from this invoice text:
        1. Invoice date (Rechnungsdatum): Provide in format YYYY-MM-DD
        2. Invoicing party (company name that issued the invoice)

        Invoice text:
        \(text)

        Respond in this exact format:
        DATE: YYYY-MM-DD
        COMPANY: Company Name

        If you cannot find the information, write "UNKNOWN" for that field.
        """

        let response = try await generate(
            systemPrompt: systemPrompt,
            userPrompt: userPrompt,
            maxTokens: config.maxTokens
        )

        // Parse response
        let lines = response.components(separatedBy: .newlines)
        var date: Date?
        var company: String?

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("DATE:") {
                let dateString = trimmed
                    .replacingOccurrences(of: "DATE:", with: "")
                    .trimmingCharacters(in: .whitespaces)

                if dateString != "UNKNOWN" {
                    date = parseDate(dateString)
                }
            } else if trimmed.hasPrefix("COMPANY:") {
                let companyName = trimmed
                    .replacingOccurrences(of: "COMPANY:", with: "")
                    .trimmingCharacters(in: .whitespaces)

                if companyName != "UNKNOWN" {
                    company = sanitizeCompanyName(companyName)
                }
            }
        }

        // Fallback: If LLM didn't find a date, try regex-based extraction
        // This catches German month formats like "September 2022" and other edge cases
        if date == nil {
            if config.verbose {
                print("Text-LLM: Date not found by LLM, trying regex fallback...")
            }
            date = extractDateWithRegex(from: text)
            if config.verbose, date != nil {
                print("Text-LLM: Regex fallback found date: \(DateUtils.formatDate(date!))")
            }
        }

        return (date, company)
    }

    /// Extract date using regex patterns (fallback for LLM failures)
    /// Uses shared DateUtils for consistent date extraction across the codebase
    private func extractDateWithRegex(from text: String) -> Date? {
        DateUtils.extractDateFromText(text)
    }

    /// Generate text using MLX LLM
    private func generate(
        systemPrompt: String,
        userPrompt: String,
        maxTokens: Int
    ) async throws -> String {
        // Load model if needed
        try await loadModelIfNeeded()

        guard let container = modelContainer else {
            throw DocScanError.modelLoadFailed("Model container not initialized")
        }

        // Generate using mlx-swift-lm
        return try await container.perform { context in
            // Prepare input with chat template
            let input = try await context.processor.prepare(
                input: .init(messages: [
                    ["role": "system", "content": systemPrompt],
                    ["role": "user", "content": userPrompt],
                ])
            )

            // Generate with streaming (collect full output)
            var fullOutput = ""

            try MLXLMCommon.generate(
                input: input,
                parameters: .init(
                    maxTokens: maxTokens,
                    temperature: Float(config.temperature)
                ),
                context: context
            ) { tokens in
                fullOutput = context.tokenizer.decode(tokens: tokens)

                if config.verbose {
                    // Show generation progress
                    print(".", terminator: "")
                }

                return .more
            }

            if config.verbose {
                print() // New line after progress dots
            }

            return fullOutput
        }
    }

    /// Load model if not already loaded
    private func loadModelIfNeeded() async throws {
        if modelContainer != nil {
            return // Already loaded
        }

        if config.verbose {
            print("Loading Text-LLM: \(defaultTextModel)")
        }

        // Load model using LLMModelFactory
        modelContainer = try await LLMModelFactory.shared.loadContainer(
            configuration: .init(id: defaultTextModel)
        ) { [self] progress in
            if config.verbose {
                let percent = Int(progress.fractionCompleted * 100)
                print("Downloading model: \(percent)%")
            }
        }

        if config.verbose {
            print("Text-LLM loaded successfully")
        }
    }

    /// Parse date string using shared utility
    private func parseDate(_ dateString: String) -> Date? {
        DateUtils.parseDate(dateString)
    }

    /// Sanitize company name using shared utility
    private func sanitizeCompanyName(_ name: String) -> String {
        StringUtils.sanitizeCompanyName(name)
    }
}
