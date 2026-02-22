@testable import DocScanCore
import XCTest

final class HuggingFaceClientTests: XCTestCase {
    var mockSession: MockURLSession!

    override func setUp() {
        super.setUp()
        mockSession = MockURLSession()
    }

    // MARK: - URL Construction

    func testSearchRequestUsesCorrectBaseURL() async throws {
        let models = [MockURLSession.makeModel(id: "test/model")]
        try mockSession.setMockModels(models)

        let client = HuggingFaceClient(session: mockSession)
        _ = try await client.searchVLMModels()

        XCTAssertEqual(mockSession.requestHistory.count, 1)
        let url = try XCTUnwrap(mockSession.requestHistory[0].url).absoluteString
        XCTAssertTrue(url.hasPrefix("https://huggingface.co/api/models"))
        XCTAssertTrue(url.contains("sort=downloads"))
    }

    // MARK: - Auth Header

    func testAuthHeaderWithToken() async throws {
        try mockSession.setMockModels([])
        let client = HuggingFaceClient(session: mockSession, apiToken: "hf_test_token")
        _ = try await client.searchVLMModels()

        let authHeader = mockSession.requestHistory[0].value(forHTTPHeaderField: "Authorization")
        XCTAssertEqual(authHeader, "Bearer hf_test_token")
    }

    func testNoAuthHeaderWithoutToken() async throws {
        try mockSession.setMockModels([])
        let client = HuggingFaceClient(session: mockSession, apiToken: nil)
        _ = try await client.searchVLMModels()

        let authHeader = mockSession.requestHistory[0].value(forHTTPHeaderField: "Authorization")
        XCTAssertNil(authHeader)
    }

    // MARK: - VLM Search

    func testVLMSearchParsesModels() async throws {
        let models = [
            MockURLSession.makeModel(id: "org/vlm-2b", downloads: 500),
            MockURLSession.makeModel(id: "org/vlm-7b", downloads: 300),
        ]
        try mockSession.setMockModels(models)

        let client = HuggingFaceClient(session: mockSession)
        let results = try await client.searchVLMModels()

        XCTAssertEqual(results.count, 2)
        XCTAssertEqual(results[0].modelId, "org/vlm-2b")
        XCTAssertEqual(results[0].downloads, 500)
        XCTAssertEqual(results[1].modelId, "org/vlm-7b")
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

    // MARK: - Pair Assembly

    func testDiscoverModelPairsIncludesCurrentPairFirst() async throws {
        let models = [MockURLSession.makeModel(id: "org/other-model")]
        try mockSession.setMockModels(models)

        let client = HuggingFaceClient(session: mockSession)
        let pairs = try await client.discoverModelPairs(
            currentVLM: "current/vlm",
            currentTextLLM: "current/text",
            count: 3
        )

        XCTAssertFalse(pairs.isEmpty)
        XCTAssertEqual(pairs[0].vlmModelName, "current/vlm")
        XCTAssertEqual(pairs[0].textModelName, "current/text")
    }

    func testDiscoverModelPairsRespectsCount() async throws {
        let models = (1 ... 10).map { MockURLSession.makeModel(id: "org/model-\($0)") }
        try mockSession.setMockModels(models)

        let client = HuggingFaceClient(session: mockSession)
        let pairs = try await client.discoverModelPairs(
            currentVLM: "current/vlm",
            currentTextLLM: "current/text",
            count: 3
        )

        XCTAssertLessThanOrEqual(pairs.count, 3)
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
            _ = try await client.searchVLMModels()
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
            _ = try await client.searchVLMModels()
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
            _ = try await client.searchVLMModels()
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

    func testRateLimitedThrows() async {
        mockSession.mockData = Data()
        mockSession.mockResponse = MockURLSession.httpResponse(statusCode: 429)

        let client = HuggingFaceClient(session: mockSession)

        do {
            _ = try await client.searchVLMModels()
            XCTFail("Expected error")
        } catch let error as DocScanError {
            if case let .huggingFaceAPIError(msg) = error {
                XCTAssertTrue(msg.contains("429"))
            } else {
                XCTFail("Expected huggingFaceAPIError")
            }
        } catch {
            XCTFail("Expected DocScanError")
        }
    }

    // MARK: - Empty Results

    func testEmptyResultsDoNotCrash() async throws {
        try mockSession.setMockModels([])
        let client = HuggingFaceClient(session: mockSession)
        let results = try await client.searchVLMModels()
        XCTAssertTrue(results.isEmpty)
    }

    // MARK: - Model URL

    func testModelURL() {
        let url = HuggingFaceClient.modelURL(for: "mlx-community/Qwen2-VL-2B-Instruct-4bit")
        XCTAssertEqual(url, "https://huggingface.co/mlx-community/Qwen2-VL-2B-Instruct-4bit")
    }
}
