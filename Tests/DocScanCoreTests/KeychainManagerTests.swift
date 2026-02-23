@testable import DocScanCore
import XCTest

final class KeychainManagerTests: XCTestCase {
    /// Unique test account to avoid conflicts with real data
    private let testAccount = "docscan-test-\(UUID().uuidString)"

    override func setUpWithError() throws {
        try super.setUpWithError()
        try XCTSkipIf(
            ProcessInfo.processInfo.environment["CI"] != nil,
            "Keychain user-presence access control requires entitlements unavailable in CI"
        )
    }

    override func tearDown() {
        // Clean up any Keychain entries created during tests
        try? KeychainManager.deleteToken(forAccount: testAccount)
        super.tearDown()
    }

    // MARK: - Save and Retrieve

    func testSaveAndRetrieve() throws {
        let token = "hf_test_token_12345"
        try KeychainManager.saveToken(token, forAccount: testAccount)

        let retrieved = try KeychainManager.retrieveToken(forAccount: testAccount)
        XCTAssertEqual(retrieved, token)
    }

    // MARK: - Retrieve Non-Existent

    func testRetrieveNonExistentReturnsNil() throws {
        let retrieved = try KeychainManager.retrieveToken(forAccount: "non-existent-account-\(UUID().uuidString)")
        XCTAssertNil(retrieved)
    }

    // MARK: - Update via Save

    func testSaveUpdatesExistingValue() throws {
        let original = "original_token"
        let updated = "updated_token"

        try KeychainManager.saveToken(original, forAccount: testAccount)
        try KeychainManager.saveToken(updated, forAccount: testAccount)

        let retrieved = try KeychainManager.retrieveToken(forAccount: testAccount)
        XCTAssertEqual(retrieved, updated)
    }

    // MARK: - Delete

    func testDeleteRemovesEntry() throws {
        let token = "token_to_delete"
        try KeychainManager.saveToken(token, forAccount: testAccount)

        try KeychainManager.deleteToken(forAccount: testAccount)

        let retrieved = try KeychainManager.retrieveToken(forAccount: testAccount)
        XCTAssertNil(retrieved)
    }

    func testDeleteNonExistentDoesNotThrow() throws {
        // Should not throw for non-existent items
        XCTAssertNoThrow(try KeychainManager.deleteToken(forAccount: "non-existent-\(UUID().uuidString)"))
    }

    // MARK: - Save (Upsert)

    func testSaveTokenNewEntry() throws {
        let token = "new_upsert_token"
        try KeychainManager.saveToken(token, forAccount: testAccount)

        let retrieved = try KeychainManager.retrieveToken(forAccount: testAccount)
        XCTAssertEqual(retrieved, token)
    }

    func testSaveTokenExistingEntry() throws {
        let original = "original_upsert"
        let updated = "updated_upsert"

        try KeychainManager.saveToken(original, forAccount: testAccount)
        try KeychainManager.saveToken(updated, forAccount: testAccount)

        let retrieved = try KeychainManager.retrieveToken(forAccount: testAccount)
        XCTAssertEqual(retrieved, updated)
    }

    // MARK: - Empty String

    func testSaveEmptyStringToken() throws {
        try KeychainManager.saveToken("", forAccount: testAccount)

        let retrieved = try KeychainManager.retrieveToken(forAccount: testAccount)
        XCTAssertEqual(retrieved, "")
    }

    // MARK: - Service Name

    func testServiceName() {
        XCTAssertEqual(KeychainManager.serviceName, "com.docscan.huggingface")
    }
}
