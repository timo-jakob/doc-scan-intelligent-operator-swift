import Foundation
import MLX
import MLXLLM
import MLXLMCommon

/// Manages text-only LLM for analyzing OCR-extracted text using mlx-swift-lm.
///
/// Marked `@unchecked Sendable` because the mutable `modelContainer` is only written once
/// during `preload()` and then read during sequential `generate()` calls. The benchmark
/// engine serialises all access (one model at a time, documents processed sequentially),
/// so no concurrent mutation is possible.
open class TextLLMManager: @unchecked Sendable {
    private let config: Configuration

    /// Model container (lazy loaded)
    private var modelContainer: ModelContainer?

    /// The model identifier used for text LLM inference
    public var modelName: String {
        config.textModelName
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
            configuration: .init(id: config.textModelName)
        ) { progress in
            progressHandler(progress.fractionCompleted)
        }
    }

    /// Analyze OCR text using Text-LLM to extract invoice data
    public func analyzeInvoiceText(
        _ text: String
    ) async throws -> OCREngine.LegacyInvoiceData {
        if config.verbose {
            print("Text-LLM: Analyzing OCR text...")
        }

        // First, check if it's an invoice using keyword detection
        let isInvoice = detectInvoice(from: text)

        guard isInvoice else {
            if config.verbose {
                print("Text-LLM: Not an invoice")
            }
            return OCREngine.LegacyInvoiceData(isInvoice: false, date: nil, company: nil)
        }

        // Extract date and company using LLM
        let extraction = try await extractInvoiceData(from: text)

        if config.verbose {
            print("Text-LLM Results:")
            print("  Is Invoice: \(isInvoice)")
            print("  Date: \(extraction.date?.description ?? "nil")")
            print("  Company: \(extraction.company ?? "nil")")
        }

        return OCREngine.LegacyInvoiceData(
            isInvoice: isInvoice,
            date: extraction.date,
            company: extraction.company
        )
    }

    /// Detect if text represents an invoice using keyword detection
    private func detectInvoice(from text: String) -> Bool {
        if config.verbose {
            print("Text-LLM: Checking if text contains invoice...")
        }

        // Use shared keyword detection from OCREngine
        let result = OCREngine.detectInvoiceKeywords(from: text)

        if config.verbose {
            print("Text-LLM: Keyword detection result: \(result.isMatch) (confidence: \(result.confidence))")
            if let reason = result.reason {
                print("  - \(reason)")
            }
        }

        return result.isMatch
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
    ) async throws -> ExtractionResult {
        let systemPrompt = documentType.extractionSystemPrompt
        let userPrompt = documentType.extractionUserPrompt(for: text)

        let response = try await generate(
            systemPrompt: systemPrompt,
            userPrompt: userPrompt,
            maxTokens: config.maxTokens
        )

        var parsed = parseExtractionResponse(response, documentType: documentType)

        // Fallback: If LLM didn't find a date, try regex-based extraction
        if parsed.date == nil {
            if config.verbose {
                print("Text-LLM: Date not found by LLM, trying regex fallback...")
            }
            let fallbackDate = extractDateWithRegex(from: text)
            if config.verbose, let fallbackDate {
                print("Text-LLM: Regex fallback found date: \(DateUtils.formatDate(fallbackDate))")
            }
            parsed = ExtractionResult(
                date: fallbackDate,
                secondaryField: parsed.secondaryField,
                patientName: parsed.patientName
            )
        }

        return parsed
    }

    /// Parse an LLM response into an ExtractionResult
    private func parseExtractionResponse(
        _ response: String,
        documentType: DocumentType
    ) -> ExtractionResult {
        let lines = response.components(separatedBy: .newlines)
        var date: Date?
        var secondaryField: String?
        var patientName: String?

        let secondaryPrefix = switch documentType {
        case .invoice: "COMPANY:"
        case .prescription: "DOCTOR:"
        }

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("DATE:") {
                let value = trimmed
                    .replacingOccurrences(of: "DATE:", with: "")
                    .trimmingCharacters(in: .whitespaces)
                if value != "UNKNOWN", value != "NOT_FOUND" {
                    date = parseDate(value)
                }
            } else if trimmed.hasPrefix(secondaryPrefix) {
                let value = trimmed
                    .replacingOccurrences(of: secondaryPrefix, with: "")
                    .trimmingCharacters(in: .whitespaces)
                if value != "UNKNOWN", value != "NOT_FOUND" {
                    secondaryField = sanitizeFieldValue(value, for: documentType)
                }
            } else if trimmed.hasPrefix("PATIENT:"),
                      documentType == .prescription {
                let value = trimmed
                    .replacingOccurrences(of: "PATIENT:", with: "")
                    .trimmingCharacters(in: .whitespaces)
                if value != "UNKNOWN", value != "NOT_FOUND" {
                    patientName = StringUtils.sanitizePatientName(value)
                }
            }
        }

        return ExtractionResult(
            date: date,
            secondaryField: secondaryField,
            patientName: patientName
        )
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

    /// Result of legacy invoice extraction (date + company)
    struct InvoiceExtraction {
        let date: Date?
        let company: String?
    }

    /// Extract invoice date and company from text using LLM with regex fallback
    private func extractInvoiceData(from text: String) async throws -> InvoiceExtraction {
        let systemPrompt = """
        You are an invoice data extraction assistant. \
        Extract information accurately and respond in the exact format requested.
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

        let parsed = parseExtractionResponse(response, documentType: .invoice)
        var date = parsed.date
        let company = parsed.secondaryField

        // Fallback: If LLM didn't find a date, try regex-based extraction
        if date == nil {
            if config.verbose {
                print("Text-LLM: Date not found by LLM, trying regex fallback...")
            }
            date = extractDateWithRegex(from: text)
            if config.verbose, let date {
                print("Text-LLM: Regex fallback found date: \(DateUtils.formatDate(date))")
            }
        }

        return InvoiceExtraction(date: date, company: company)
    }

    /// Extract date using regex patterns (fallback for LLM failures)
    /// Uses shared DateUtils for consistent date extraction across the codebase
    private func extractDateWithRegex(from text: String) -> Date? {
        DateUtils.extractDateFromText(text)
    }
}

// MARK: - LLM Generation

extension TextLLMManager {
    /// Generate text using MLX LLM
    func generate(
        systemPrompt: String,
        userPrompt: String,
        maxTokens: Int
    ) async throws -> String {
        // Load model if needed
        try await loadModelIfNeeded()

        guard let container = modelContainer else {
            throw DocScanError.modelLoadFailed("Model container not initialized")
        }

        // Generate using mlx-swift-lm (AsyncStream API)
        return try await container.perform { context in
            // Prepare input with chat template
            let input = try await context.processor.prepare(
                input: .init(messages: [
                    ["role": "system", "content": systemPrompt],
                    ["role": "user", "content": userPrompt],
                ])
            )

            let stream = try MLXLMCommon.generate(
                input: input,
                parameters: .init(
                    maxTokens: maxTokens,
                    temperature: Float(config.temperature)
                ),
                context: context
            )

            var fullOutput = ""
            for await generation in stream {
                switch generation {
                case let .chunk(text):
                    fullOutput += text
                    if config.verbose {
                        print(".", terminator: "")
                    }
                case .info:
                    break
                case .toolCall:
                    if config.verbose {
                        print("[warn] unexpected toolCall event from TextLLM — ignored")
                    }
                }
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
            print("Loading Text-LLM: \(config.textModelName)")
        }

        // Load model using LLMModelFactory
        modelContainer = try await LLMModelFactory.shared.loadContainer(
            configuration: .init(id: config.textModelName)
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
    func parseDate(_ dateString: String) -> Date? {
        DateUtils.parseDate(dateString)
    }

    /// Sanitize company name using shared utility
    func sanitizeCompanyName(_ name: String) -> String {
        StringUtils.sanitizeCompanyName(name)
    }
}
