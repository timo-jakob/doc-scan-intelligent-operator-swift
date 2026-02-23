import AppKit
@testable import DocScanCore
import Foundation

/// Mock DocumentDetector factory for testing BenchmarkEngine
final class MockDocumentDetectorFactory: DocumentDetectorFactory {
    var mockVLMResponse: String = "YES"
    var mockDate: Date?
    var mockSecondaryField: String?
    var mockPatientName: String?
    var shouldThrowError: Bool = false
    var errorToThrow: Error = DocScanError.inferenceError("Mock error")

    /// Count of detectors created
    private(set) var detectorsCreated = 0

    func preloadModels(config _: Configuration) async throws {
        // No-op for tests — no real models to download
    }

    func releaseModels() {
        // No-op for tests — no GPU resources to release
    }

    func makeDetector(config: Configuration, documentType: DocumentType) async throws -> DocumentDetector {
        detectorsCreated += 1

        if shouldThrowError {
            throw errorToThrow
        }

        let mockVLM = MockVLMProvider()
        mockVLM.mockResponse = mockVLMResponse

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
