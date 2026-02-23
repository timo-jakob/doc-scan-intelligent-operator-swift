import AppKit
@testable import DocScanCore
import Foundation

/// Mock DocumentDetector factory for testing BenchmarkEngine.
/// @unchecked Sendable is safe here: properties are set during synchronous test setup
/// and only read during async test execution on a single test thread.
final class MockDocumentDetectorFactory: DocumentDetectorFactory, @unchecked Sendable {
    var mockVLMResponse: String = "YES"
    var mockDate: Date?
    var mockSecondaryField: String?
    var mockPatientName: String?
    var shouldThrowError: Bool = false
    var errorToThrow: Error = DocScanError.inferenceError("Mock error")
    var shouldThrowOnPreload: Bool = false
    var preloadError: Error = DocScanError.modelLoadFailed("Mock preload error")
    var mockVLMDelay: TimeInterval = 0

    /// Count of detectors created
    private(set) var detectorsCreated = 0
    /// Count of releaseModels calls
    private(set) var releaseModelsCalled = 0

    func preloadModels(config _: Configuration) async throws {
        if shouldThrowOnPreload {
            throw preloadError
        }
    }

    func releaseModels() {
        releaseModelsCalled += 1
    }

    func makeDetector(config: Configuration, documentType: DocumentType) async throws -> DocumentDetector {
        detectorsCreated += 1

        if shouldThrowError {
            throw errorToThrow
        }

        let mockVLM = MockVLMProvider()
        mockVLM.mockResponse = mockVLMResponse
        mockVLM.mockDelay = mockVLMDelay

        let mockText = MockTextLLMManager(config: config)
        mockText.mockDate = mockDate
        mockText.mockSecondaryField = mockSecondaryField
        mockText.mockPatientName = mockPatientName

        return DocumentDetector(
            config: config,
            documentType: documentType,
            vlmProvider: mockVLM,
            textLLM: mockText
        )
    }
}
