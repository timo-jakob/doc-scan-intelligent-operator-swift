import Foundation

/// Protocol abstracting URLSession for testability
public protocol URLSessionProtocol: Sendable {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: URLSessionProtocol {}

/// A model discovered from Hugging Face
public struct HFModel: Codable, Equatable, Sendable {
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
public enum HFGated: Codable, Equatable, Sendable {
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

/// Client for querying the Hugging Face API
public final class HuggingFaceClient: Sendable {
    private let session: URLSessionProtocol
    private let apiToken: String?
    private let baseURL: String
    private let retryDelays: [UInt64]

    public static let defaultBaseURL = "https://" + "huggingface.co/api"

    public init(
        session: URLSessionProtocol = URLSession.shared,
        apiToken: String? = nil,
        baseURL: String = HuggingFaceClient.defaultBaseURL,
        retryDelays: [UInt64] = [2, 5, 10]
    ) {
        self.session = session
        self.apiToken = apiToken
        self.baseURL = baseURL
        self.retryDelays = retryDelays
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
        let path = "models?search=\(encodedQuery)&sort=downloads&direction=-1&limit=\(limit)"
        return try await fetchJSON(path: path)
    }

    private func fetchModel(_ modelId: String) async throws -> HFModel {
        let encodedId = modelId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? modelId
        return try await fetchJSON(path: "models/\(encodedId)")
    }

    private func fetchJSON<T: Decodable>(path: String) async throws -> T {
        let urlString = "\(baseURL)/\(path)"
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
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func performRequest(_ request: URLRequest) async throws -> (Data, URLResponse) {
        let maxAttempts = retryDelays.count + 1

        for attempt in 0 ..< maxAttempts {
            let data: Data
            let response: URLResponse
            do {
                (data, response) = try await session.data(for: request)
            } catch let error as DocScanError {
                throw error
            } catch {
                throw DocScanError.networkError(error.localizedDescription)
            }

            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 429,
               attempt < retryDelays.count {
                try await Task.sleep(for: .seconds(retryDelays[attempt]))
                continue
            }

            return (data, response)
        }

        // Unreachable, but satisfies the compiler
        throw DocScanError.huggingFaceAPIError("Rate limited (429): Too many requests after retries")
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
            throw DocScanError.huggingFaceAPIError("Rate limited (429): Too many requests after retries")
        default:
            throw DocScanError.huggingFaceAPIError("HTTP \(httpResponse.statusCode)")
        }
    }
}
