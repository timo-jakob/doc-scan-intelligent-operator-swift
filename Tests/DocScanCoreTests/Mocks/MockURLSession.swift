@testable import DocScanCore
import Foundation

/// Mock URLSession for testing HuggingFaceClient without network calls
final class MockURLSession: URLSessionProtocol, @unchecked Sendable {
    var mockData: Data?
    var mockResponse: URLResponse?
    var mockError: Error?
    var requestHistory: [URLRequest] = []

    /// Create a successful HTTP response with given status code
    static func httpResponse(statusCode: Int = 200, url: URL? = nil) -> HTTPURLResponse {
        HTTPURLResponse(
            url: url ?? URL(string: "https://huggingface.co/api/models")!,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: nil
        )!
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        requestHistory.append(request)
        if let error = mockError {
            throw error
        }
        return (
            mockData ?? Data(),
            mockResponse ?? Self.httpResponse()
        )
    }

    /// Configure mock to return JSON-encoded array of HFModels
    func setMockModels(_ models: [HFModel]) throws {
        let encoder = JSONEncoder()
        mockData = try encoder.encode(models)
        mockResponse = Self.httpResponse()
    }

    /// Configure mock to return a single HFModel
    func setMockModel(_ model: HFModel) throws {
        let encoder = JSONEncoder()
        mockData = try encoder.encode(model)
        mockResponse = Self.httpResponse()
    }

    /// Helper to create a test HFModel
    static func makeModel(
        id: String,
        downloads: Int = 100,
        tags: [String]? = nil,
        gated: HFGated? = nil
    ) -> HFModel {
        HFModel(
            modelId: id,
            downloads: downloads,
            tags: tags,
            lastModified: "2025-01-01T00:00:00.000Z",
            gated: gated
        )
    }
}
