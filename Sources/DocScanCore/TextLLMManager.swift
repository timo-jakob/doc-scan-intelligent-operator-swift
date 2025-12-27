import Foundation
import MLX
import MLXLLM
import MLXLMCommon

/// Manages text-only LLM for analyzing OCR-extracted text using mlx-swift-lm
public class TextLLMManager {
    private let config: Configuration

    // Default text-only model for analyzing OCR results (Qwen2.5-7B optimized for Apple Silicon)
    private let defaultTextModel = "mlx-community/Qwen2.5-7B-Instruct-4bit"

    // Model container (lazy loaded)
    private var modelContainer: ModelContainer?

    public init(config: Configuration) {
        self.config = config
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
            if let reason = reason {
                print("  - \(reason)")
            }
        }

        return isInvoice
    }

    /// Extract date and company from text using LLM (public API for Phase 2)
    public func extractDateAndCompany(from text: String) async throws -> (Date?, String?) {
        return try await extractInvoiceData(from: text)
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
            if config.verbose && date != nil {
                print("Text-LLM: Regex fallback found date: \(DateUtils.formatDate(date!))")
            }
        }

        return (date, company)
    }

    /// Extract date using regex patterns (fallback for LLM failures)
    private func extractDateWithRegex(from text: String) -> Date? {
        // Common date patterns
        let patterns = [
            // ISO format: 2024-12-22
            "\\b(\\d{4})-(\\d{2})-(\\d{2})\\b",
            // European format: 22.12.2024 or 22/12/2024
            "\\b(\\d{2})[./](\\d{2})[./](\\d{4})\\b",
            // Colon-separated (OCR artifact): 22:12:2024
            "\\b(\\d{2}):(\\d{2}):(\\d{4})\\b"
        ]

        // Try to find date near common keywords first (more reliable)
        let dateKeywords = [
            "rechnungsdatum:", "invoice date:", "datum:", "date:",
            "rechnungsdatum", "invoice date", "facture du:", "fecha:"
        ]

        for keyword in dateKeywords {
            if let range = text.range(of: keyword, options: .caseInsensitive) {
                let afterKeyword = String(text[range.upperBound...])
                let nearbyText = String(afterKeyword.prefix(40))

                for pattern in patterns {
                    if let date = extractDateWithPattern(nearbyText, pattern: pattern) {
                        return date
                    }
                }

                // Also try German month format near keywords
                if let date = extractGermanMonthDate(from: nearbyText) {
                    return date
                }
            }
        }

        // Try German month format anywhere in text FIRST
        // This is preferred over numeric dates because billing period dates like "September 2022"
        // are more likely to be the invoice date than other dates like payment due dates
        if let date = extractGermanMonthDate(from: text) {
            return date
        }

        // Fallback: try any numeric date pattern in the text
        for pattern in patterns {
            if let date = extractDateWithPattern(text, pattern: pattern) {
                return date
            }
        }

        return nil
    }

    /// Extract date from German month format like "September 2022"
    private func extractGermanMonthDate(from text: String) -> Date? {
        let germanMonths = [
            "januar", "februar", "märz", "maerz", "april", "mai", "juni",
            "juli", "august", "september", "oktober", "november", "dezember",
            "jan", "feb", "mrz", "apr", "jun", "jul", "aug", "sep", "sept", "okt", "nov", "dez"
        ]

        let lowercased = text.lowercased()
        for month in germanMonths {
            // Use word boundary regex to avoid false positives (e.g., "mai" in "email")
            let monthPattern = "\\b\(NSRegularExpression.escapedPattern(for: month))\\b"
            guard let monthRegex = try? NSRegularExpression(pattern: monthPattern, options: .caseInsensitive),
                  let monthMatch = monthRegex.firstMatch(in: lowercased, range: NSRange(lowercased.startIndex..., in: lowercased)),
                  let monthRange = Range(monthMatch.range, in: lowercased) else {
                continue
            }

            // Look for a 4-digit year after the month
            let afterMonthString = String(String(lowercased[monthRange.upperBound...]).prefix(20))
            let yearPattern = "\\b(20\\d{2})\\b"

            guard let yearRegex = try? NSRegularExpression(pattern: yearPattern),
                  let yearMatch = yearRegex.firstMatch(in: afterMonthString, range: NSRange(afterMonthString.startIndex..., in: afterMonthString)),
                  let yearRange = Range(yearMatch.range, in: afterMonthString) else {
                continue
            }

            let yearString = afterMonthString[yearRange]
            let monthYearString = "\(month) \(yearString)"
            if let date = DateUtils.parseDate(monthYearString) {
                return date
            }
        }

        return nil
    }

    /// Extract date using regex pattern
    private func extractDateWithPattern(_ text: String, pattern: String) -> Date? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }

        let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))

        for match in matches {
            if let range = Range(match.range, in: text) {
                let dateString = String(text[range])
                if let date = DateUtils.parseDate(dateString) {
                    return date
                }
            }
        }

        return nil
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
                    ["role": "user", "content": userPrompt]
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
            if self.config.verbose {
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
        return DateUtils.parseDate(dateString)
    }

    /// Sanitize company name using shared utility
    private func sanitizeCompanyName(_ name: String) -> String {
        return StringUtils.sanitizeCompanyName(name)
    }
}
