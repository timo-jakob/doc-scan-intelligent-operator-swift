import Foundation
import MLX
import MLXLLM
import MLXLMCommon

// MARK: - TextLLM Provider Protocol

/// Protocol for text-based LLM providers
/// Enables dependency injection and testing without actual model loading
public protocol TextLLMProviding: Sendable {
    /// The model identifier used for text LLM inference
    var modelName: String { get }

    /// Preload the text LLM model so it is ready before processing begins.
    func preload(progressHandler: @escaping @Sendable (Double) -> Void) async throws

    /// Generic data extraction for any document type
    func extractData(
        for documentType: DocumentType,
        from text: String
    ) async throws -> ExtractionResult

    /// Generate text from system and user prompts
    func generate(
        systemPrompt: String,
        userPrompt: String,
        maxTokens: Int
    ) async throws -> String
}

// MARK: - TextLLM Manager

/// Manages text-only LLM for analyzing OCR-extracted text using mlx-swift-lm.
public actor TextLLMManager: TextLLMProviding {
    private let config: Configuration

    /// Model container (lazy loaded)
    private var modelContainer: ModelContainer?

    /// The model identifier used for text LLM inference
    public nonisolated var modelName: String {
        config.textModelName
    }

    public init(config: Configuration) {
        self.config = config
    }

    /// Preload the text LLM model so it is ready before processing begins.
    /// Calls progressHandler with fractions 0.0–1.0 only when a download is required.
    /// If the model is already cached locally the handler is never called.
    public func preload(progressHandler: @escaping @Sendable (Double) -> Void) async throws {
        guard modelContainer == nil else { return }

        modelContainer = try await LLMModelFactory.shared.loadContainer(
            configuration: .init(id: config.textModelName)
        ) { progress in
            progressHandler(progress.fractionCompleted)
        }
    }

    /// Generic data extraction for any document type
    /// Returns extracted date, secondary field (company/doctor), and optional patient name
    public func extractData(
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
                    date = DateUtils.parseDate(value)
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

    /// Extract date using regex patterns (fallback for LLM failures)
    /// Uses shared DateUtils for consistent date extraction across the codebase
    private func extractDateWithRegex(from text: String) -> Date? {
        DateUtils.extractDateFromText(text)
    }

    // MARK: - LLM Generation

    /// Generate text using MLX LLM.
    public func generate(
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
                    temperature: Float(self.config.temperature)
                ),
                context: context
            )

            var fullOutput = ""
            for await generation in stream {
                switch generation {
                case let .chunk(text):
                    fullOutput += text
                    if self.config.verbose {
                        print(".", terminator: "")
                    }
                case .info:
                    break
                case .toolCall:
                    if self.config.verbose {
                        print("[warn] unexpected toolCall event from TextLLM — ignored")
                    }
                }
            }

            if self.config.verbose {
                print() // New line after progress dots
            }

            return fullOutput
        }
    }
}

// MARK: - Private Helpers

extension TextLLMManager {
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
}
