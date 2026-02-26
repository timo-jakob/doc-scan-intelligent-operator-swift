@testable import DocScanCore
import XCTest

final class HuggingFaceClientTests: XCTestCase {
    var mockSession: MockURLSession!

    override func setUp() {
        super.setUp()
        mockSession = MockURLSession()
    }

    // MARK: - URL Construction

    func testFamilySearchUsesCorrectURL() async throws {
        let models = [MockURLSession.makeModel(id: "test/model", tags: ["mlx"])]
        try mockSession.setMockModels(models)

        let client = HuggingFaceClient(session: mockSession)
        _ = try await client.searchVLMFamily("Qwen3-VL")

        XCTAssertEqual(mockSession.requestHistory.count, 1)
        let url = try XCTUnwrap(mockSession.requestHistory[0].url).absoluteString
        XCTAssertTrue(url.hasPrefix("https://huggingface.co/api/models"))
        XCTAssertTrue(url.contains("sort=downloads"))
        XCTAssertTrue(url.contains("pipeline_tag=image-text-to-text"))
        XCTAssertTrue(url.contains("Qwen3-VL"))
    }

    // MARK: - Auth Header

    func testAuthHeaderWithToken() async throws {
        try mockSession.setMockModels([])
        let client = HuggingFaceClient(session: mockSession, apiToken: "hf_test_token")
        _ = try await client.searchVLMFamily("test")

        let authHeader = mockSession.requestHistory[0].value(forHTTPHeaderField: "Authorization")
        XCTAssertEqual(authHeader, "Bearer hf_test_token")
    }

    func testNoAuthHeaderWithoutToken() async throws {
        try mockSession.setMockModels([])
        let client = HuggingFaceClient(session: mockSession, apiToken: nil)
        _ = try await client.searchVLMFamily("test")

        let authHeader = mockSession.requestHistory[0].value(forHTTPHeaderField: "Authorization")
        XCTAssertNil(authHeader)
    }

    // MARK: - VLM Family Search

    func testFamilySearchParsesModels() async throws {
        let models = [
            MockURLSession.makeModel(id: "org/vlm-2b", downloads: 500, tags: ["mlx", "image-text-to-text"]),
            MockURLSession.makeModel(id: "org/vlm-7b", downloads: 300, tags: ["mlx", "image-text-to-text"]),
        ]
        try mockSession.setMockModels(models)

        let client = HuggingFaceClient(session: mockSession)
        let results = try await client.searchVLMFamily("test-vlm")

        XCTAssertEqual(results.count, 2)
        XCTAssertEqual(results[0].modelId, "org/vlm-2b")
        XCTAssertEqual(results[0].downloads, 500)
        XCTAssertEqual(results[1].modelId, "org/vlm-7b")
    }

    func testFamilySearchFiltersNonMLXModels() async throws {
        let models = [
            MockURLSession.makeModel(id: "org/mlx-model-a", downloads: 500, tags: ["mlx", "image-text-to-text"]),
            MockURLSession.makeModel(
                id: "org/non-mlx-model", downloads: 400,
                tags: ["transformers", "image-text-to-text"]
            ),
            MockURLSession.makeModel(id: "org/mlx-model-b", downloads: 300, tags: ["mlx", "safetensors"]),
        ]
        try mockSession.setMockModels(models)

        let client = HuggingFaceClient(session: mockSession)
        let results = try await client.searchVLMFamily("test")

        XCTAssertEqual(results.count, 2)
        XCTAssertEqual(results[0].modelId, "org/mlx-model-a")
        XCTAssertEqual(results[1].modelId, "org/mlx-model-b")
    }

    func testFamilySearchFiltersModelsWithNilTags() async throws {
        let models = [
            MockURLSession.makeModel(id: "org/tagged-model", downloads: 500, tags: ["mlx"]),
            MockURLSession.makeModel(id: "org/untagged-model", downloads: 400, tags: nil),
        ]
        try mockSession.setMockModels(models)

        let client = HuggingFaceClient(session: mockSession)
        let results = try await client.searchVLMFamily("test")

        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].modelId, "org/tagged-model")
    }

    func testFamilySearchOverFetchesToCompensateForFiltering() async throws {
        try mockSession.setMockModels([])

        let client = HuggingFaceClient(session: mockSession)
        _ = try await client.searchVLMFamily("test", limit: 10)

        // API receives limit * 3 to compensate for client-side MLX filtering
        let url = try XCTUnwrap(mockSession.requestHistory[0].url).absoluteString
        XCTAssertTrue(url.contains("limit=30"))
    }

    func testFamilySearchUsesDefaultLimitOf25() async throws {
        try mockSession.setMockModels([])

        let client = HuggingFaceClient(session: mockSession)
        _ = try await client.searchVLMFamily("test")

        // Default limit=25, over-fetched to 75
        let url = try XCTUnwrap(mockSession.requestHistory[0].url).absoluteString
        XCTAssertTrue(url.contains("limit=75"))
    }

    func testFamilySearchTruncatesResultsToRequestedLimit() async throws {
        let models = (0 ..< 10).map { idx in
            MockURLSession.makeModel(id: "org/model-\(idx)", downloads: 100 - idx, tags: ["mlx"])
        }
        try mockSession.setMockModels(models)

        let client = HuggingFaceClient(session: mockSession)
        let results = try await client.searchVLMFamily("test", limit: 3)

        XCTAssertEqual(results.count, 3)
    }

    func testFamilySearchRetainsGatedModelsWithCorrectFlag() async throws {
        let models = [
            MockURLSession.makeModel(id: "org/open-model", tags: ["mlx"], gated: .bool(false)),
            MockURLSession.makeModel(id: "org/gated-model", tags: ["mlx"], gated: .string("auto")),
        ]
        try mockSession.setMockModels(models)

        let client = HuggingFaceClient(session: mockSession)
        let results = try await client.searchVLMFamily("test")

        XCTAssertEqual(results.count, 2)
        XCTAssertFalse(results[0].isGated)
        XCTAssertTrue(results[1].isGated)
    }

    func testFamilySearchWithEmptyStringReturnsResults() async throws {
        let models = [
            MockURLSession.makeModel(id: "org/some-model", tags: ["mlx"]),
        ]
        try mockSession.setMockModels(models)

        let client = HuggingFaceClient(session: mockSession)
        let results = try await client.searchVLMFamily("")

        // Empty query is sent to the API; results depend on what the API returns
        XCTAssertEqual(results.count, 1)
    }

    // MARK: - Text Search

    func testTextSearchParsesModels() async throws {
        let models = [
            MockURLSession.makeModel(id: "org/text-7b", downloads: 1000),
        ]
        try mockSession.setMockModels(models)

        let client = HuggingFaceClient(session: mockSession)
        let results = try await client.searchTextModels()

        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].modelId, "org/text-7b")
    }

    // MARK: - Gated Model Detection

    func testGatedModelDetectionBoolTrue() async throws {
        let model = MockURLSession.makeModel(id: "org/gated-model", gated: .bool(true))
        try mockSession.setMockModel(model)

        let client = HuggingFaceClient(session: mockSession)
        let isGated = try await client.isModelGated("org/gated-model")
        XCTAssertTrue(isGated)
    }

    func testGatedModelDetectionBoolFalse() async throws {
        let model = MockURLSession.makeModel(id: "org/open-model", gated: .bool(false))
        try mockSession.setMockModel(model)

        let client = HuggingFaceClient(session: mockSession)
        let isGated = try await client.isModelGated("org/open-model")
        XCTAssertFalse(isGated)
    }

    func testGatedModelDetectionString() async throws {
        let model = MockURLSession.makeModel(id: "org/gated-model", gated: .string("auto"))
        try mockSession.setMockModel(model)

        let client = HuggingFaceClient(session: mockSession)
        let isGated = try await client.isModelGated("org/gated-model")
        XCTAssertTrue(isGated)
    }

    // MARK: - Network Error

    func testNetworkErrorThrows() async {
        mockSession.mockError = NSError(domain: "NSURLErrorDomain", code: -1009, userInfo: [
            NSLocalizedDescriptionKey: "The Internet connection appears to be offline.",
        ])

        let client = HuggingFaceClient(session: mockSession)

        do {
            _ = try await client.searchVLMFamily("test")
            XCTFail("Expected error to be thrown")
        } catch let error as DocScanError {
            if case let .networkError(msg) = error {
                XCTAssertTrue(msg.contains("offline") || msg.contains("Internet"))
            } else {
                XCTFail("Expected networkError, got \(error)")
            }
        } catch {
            XCTFail("Expected DocScanError, got \(error)")
        }
    }

    // MARK: - API Error Responses

    func testUnauthorizedThrows() async {
        mockSession.mockData = Data()
        mockSession.mockResponse = MockURLSession.httpResponse(statusCode: 401)

        let client = HuggingFaceClient(session: mockSession)

        do {
            _ = try await client.searchVLMFamily("test")
            XCTFail("Expected error")
        } catch let error as DocScanError {
            if case let .huggingFaceAPIError(msg) = error {
                XCTAssertTrue(msg.contains("401"))
            } else {
                XCTFail("Expected huggingFaceAPIError, got \(error)")
            }
        } catch {
            XCTFail("Expected DocScanError")
        }
    }

    func testForbiddenThrows() async {
        mockSession.mockData = Data()
        mockSession.mockResponse = MockURLSession.httpResponse(statusCode: 403)

        let client = HuggingFaceClient(session: mockSession)

        do {
            _ = try await client.searchVLMFamily("test")
            XCTFail("Expected error")
        } catch let error as DocScanError {
            if case let .huggingFaceAPIError(msg) = error {
                XCTAssertTrue(msg.contains("403"))
            } else {
                XCTFail("Expected huggingFaceAPIError")
            }
        } catch {
            XCTFail("Expected DocScanError")
        }
    }

    func testRateLimitedRetriesThenThrows() async {
        mockSession.mockData = Data()
        mockSession.mockResponse = MockURLSession.httpResponse(statusCode: 429)

        // Zero-delay retries for fast tests; 2 entries = 3 total attempts
        let client = HuggingFaceClient(session: mockSession, retryDelays: [0, 0])

        do {
            _ = try await client.searchVLMFamily("test")
            XCTFail("Expected error")
        } catch let error as DocScanError {
            if case let .huggingFaceAPIError(msg) = error {
                XCTAssertTrue(msg.contains("429"))
            } else {
                XCTFail("Expected huggingFaceAPIError, got \(error)")
            }
        } catch {
            XCTFail("Expected DocScanError")
        }

        // 1 initial + 2 retries = 3 requests total
        XCTAssertEqual(mockSession.requestHistory.count, 3)
    }

    // MARK: - Empty Results

    func testEmptyResultsDoNotCrash() async throws {
        try mockSession.setMockModels([])
        let client = HuggingFaceClient(session: mockSession)
        let results = try await client.searchVLMFamily("nonexistent")
        XCTAssertTrue(results.isEmpty)
    }

    // MARK: - Model URL

    func testModelURL() {
        let url = HuggingFaceClient.modelURL(for: "mlx-community/Qwen2-VL-2B-Instruct-4bit")
        XCTAssertEqual(url, "https://huggingface.co/mlx-community/Qwen2-VL-2B-Instruct-4bit")
    }

    func testModelURLPercentEncodesSpaces() {
        // URLComponents handles the encoding; spaces must not appear in the result
        let url = HuggingFaceClient.modelURL(for: "org/model with spaces")
        XCTAssertEqual(url, "https://huggingface.co/org/model%20with%20spaces")
    }

    // MARK: - Fallback path (tested via the extracted helper)

    func testFallbackModelURLPreservesModelId() {
        let url = HuggingFaceClient.fallbackModelURL(for: "org/model")
        XCTAssertEqual(url, "https://huggingface.co/org/model")
    }

    func testFallbackModelURLPercentEncodesUnsafeCharacters() {
        let url = HuggingFaceClient.fallbackModelURL(for: "org/model with spaces")
        // .urlPathAllowed preserves '/' but encodes spaces
        XCTAssertEqual(url, "https://huggingface.co/org/model%20with%20spaces")
        XCTAssertFalse(url.contains(" "))
    }

    func testFallbackModelURLHandlesEmptyString() {
        let url = HuggingFaceClient.fallbackModelURL(for: "")
        XCTAssertEqual(url, "https://huggingface.co/")
    }
}
