import AppKit
@testable import DocScanCore
import PDFKit
import XCTest

// MARK: - Mock VLM Provider

/// Mock VLM provider for testing without actual model loading
final class MockVLMProvider: VLMProvider, @unchecked Sendable {
    /// Configure the mock response
    var mockResponse: String = "YES"
    var shouldThrowError: Bool = false
    var errorToThrow: Error = DocScanError.modelLoadFailed("Mock error")
    var mockDelay: TimeInterval = 0

    /// Track calls for verification
    private(set) var generateFromImageCallCount = 0
    private(set) var lastPrompt: String?
    private(set) var lastImage: NSImage?

    func generateFromImage(
        _ image: NSImage,
        prompt: String,
        modelName _: String?
    ) async throws -> String {
        generateFromImageCallCount += 1
        lastPrompt = prompt
        lastImage = image

        if mockDelay > 0 {
            try await Task.sleep(nanoseconds: UInt64(mockDelay * 1_000_000_000))
        }

        if shouldThrowError {
            throw errorToThrow
        }

        return mockResponse
    }

    func reset() {
        generateFromImageCallCount = 0
        lastPrompt = nil
        lastImage = nil
        mockResponse = "YES"
        shouldThrowError = false
    }
}

// MARK: - Mock TextLLM Manager

/// Mock TextLLM manager for testing without actual model loading
final class MockTextLLMManager: TextLLMManager {
    var mockDate: Date?
    var mockSecondaryField: String?
    var mockPatientName: String?
    var shouldThrowError: Bool = false
    var errorToThrow: Error = DocScanError.inferenceError("Mock TextLLM error")

    override func extractData(
        for _: DocumentType,
        from _: String
    ) async throws -> ExtractionResult {
        if shouldThrowError {
            throw errorToThrow
        }
        return ExtractionResult(
            date: mockDate,
            secondaryField: mockSecondaryField,
            patientName: mockPatientName
        )
    }
}
