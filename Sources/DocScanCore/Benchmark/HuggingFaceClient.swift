import Foundation

/// Protocol abstracting URLSession for testability
public protocol URLSessionProtocol: Sendable {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: URLSessionProtocol {}

/// A model discovered from Hugging Face
public struct HFModel: Codable, Equatable {
    public let modelId: String
    public let downloads: Int?
    public let tags: [String]?
    public let lastModified: String?
    public let gated: HFGated?

    public var isGated: Bool {
        switch gated {
        case let .bool(value): value
        case .string: true
        case nil: false
        }
    }

    enum CodingKeys: String, CodingKey {
        case modelId
        case downloads
        case tags
        case lastModified
        case gated
    }
}

/// Hugging Face models can have gated as bool or string
public enum HFGated: Codable, Equatable {
    case bool(Bool)
    case string(String)

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let boolVal = try? container.decode(Bool.self) {
            self = .bool(boolVal)
        } else if let strVal = try? container.decode(String.self) {
            self = .string(strVal)
        } else {
            self = .bool(false)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .bool(value):
            try container.encode(value)
        case let .string(value):
            try container.encode(value)
        }
    }
}

/// A pair of VLM + TextLLM models for benchmarking
public struct ModelPair: Equatable {
    public let vlmModelName: String
    public let textModelName: String

    public init(vlmModelName: String, textModelName: String) {
        self.vlmModelName = vlmModelName
        self.textModelName = textModelName
    }
}

/// Client for querying the Hugging Face API
public class HuggingFaceClient {
    private let session: URLSessionProtocol
    private let apiToken: String?
    private let baseURL = "https://huggingface.co/api"

    public init(session: URLSessionProtocol = URLSession.shared, apiToken: String? = nil) {
        self.session = session
        self.apiToken = apiToken
    }

    /// Search for VLM models on Hugging Face
    public func searchVLMModels(limit: Int = 10) async throws -> [HFModel] {
        let query = "mlx VLM instruct 4bit"
        return try await searchModels(query: query, limit: limit)
    }

    /// Search for text LLM models on Hugging Face
    public func searchTextModels(limit: Int = 10) async throws -> [HFModel] {
        let query = "mlx instruct 4bit"
        return try await searchModels(query: query, limit: limit)
    }

    /// Discover model pairs for benchmarking
    /// Generates the full cross-product of all VLM × text model combinations
    public func discoverModelPairs(
        currentVLM: String,
        currentTextLLM: String,
        count: Int = 5
    ) async throws -> [ModelPair] {
        let vlmModels = try await searchVLMModels(limit: count * 2)
        let textModels = try await searchTextModels(limit: count * 2)

        // Build unique VLM and text model lists, current models first
        var allVLMs = [currentVLM]
        for model in vlmModels where model.modelId != currentVLM {
            allVLMs.append(model.modelId)
        }

        var allTexts = [currentTextLLM]
        for model in textModels where model.modelId != currentTextLLM {
            allTexts.append(model.modelId)
        }

        // Full cross-product, current pair first
        var pairs: [ModelPair] = []
        for vlm in allVLMs {
            for text in allTexts {
                pairs.append(ModelPair(vlmModelName: vlm, textModelName: text))
            }
        }

        return Array(pairs.prefix(count))
    }

    /// Check if a model is gated
    public func isModelGated(_ modelId: String) async throws -> Bool {
        let model = try await fetchModel(modelId)
        return model.isGated
    }

    /// Get the Hugging Face URL for a model
    public static func modelURL(for modelId: String) -> String {
        "https://huggingface.co/\(modelId)"
    }

    // MARK: - Private

    private func searchModels(query: String, limit: Int) async throws -> [HFModel] {
        let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        let urlString = "\(baseURL)/models?search=\(encodedQuery)&sort=downloads&direction=-1&limit=\(limit)"

        guard let url = URL(string: urlString) else {
            throw DocScanError.huggingFaceAPIError("Invalid URL: \(urlString)")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        if let token = apiToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await performRequest(request)
        try validateResponse(response)

        let decoder = JSONDecoder()
        return try decoder.decode([HFModel].self, from: data)
    }

    private func fetchModel(_ modelId: String) async throws -> HFModel {
        let encodedId = modelId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? modelId
        let urlString = "\(baseURL)/models/\(encodedId)"

        guard let url = URL(string: urlString) else {
            throw DocScanError.huggingFaceAPIError("Invalid URL: \(urlString)")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        if let token = apiToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await performRequest(request)
        try validateResponse(response)

        let decoder = JSONDecoder()
        return try decoder.decode(HFModel.self, from: data)
    }

    private func performRequest(_ request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await session.data(for: request)
        } catch let error as DocScanError {
            throw error
        } catch {
            throw DocScanError.networkError(error.localizedDescription)
        }
    }

    private func validateResponse(_ response: URLResponse) throws {
        guard let httpResponse = response as? HTTPURLResponse else { return }

        switch httpResponse.statusCode {
        case 200 ..< 300:
            return
        case 401:
            throw DocScanError.huggingFaceAPIError("Unauthorized (401): Invalid or missing API token")
        case 403:
            throw DocScanError.huggingFaceAPIError("Forbidden (403): Insufficient permissions")
        case 429:
            throw DocScanError.huggingFaceAPIError("Rate limited (429): Too many requests, please try again later")
        default:
            throw DocScanError.huggingFaceAPIError("HTTP \(httpResponse.statusCode)")
        }
    }
}
