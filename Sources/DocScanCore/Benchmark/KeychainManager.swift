import Foundation
import Security

/// Manages secure storage of API tokens in the macOS Keychain
public enum KeychainManager {
    /// Service identifier for Keychain entries
    public static let serviceName = "com.docscan.huggingface"

    /// Store a new token in the Keychain (use saveToken for upsert).
    /// Returns the OSStatus so the caller can distinguish duplicate-item from real errors.
    private static func storeToken(_ token: String, forAccount account: String) throws -> OSStatus {
        guard let tokenData = token.data(using: .utf8) else {
            throw DocScanError.keychainError("Failed to encode token")
        }

        var accessError: Unmanaged<CFError>?
        guard let accessControl = SecAccessControlCreateWithFlags(
            nil,
            kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            .userPresence,
            &accessError
        ) else {
            let message = accessError?.takeRetainedValue().localizedDescription ?? "unknown error"
            throw DocScanError.keychainError("Failed to create access control: \(message)")
        }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account,
            kSecValueData as String: tokenData,
            kSecAttrAccessControl as String: accessControl,
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess || status == errSecDuplicateItem else {
            throw DocScanError.keychainError(
                "Failed to store token: \(keychainErrorMessage(status))"
            )
        }
        return status
    }

    /// Retrieve a token from the Keychain
    public static func retrieveToken(forAccount account: String) throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecItemNotFound {
            return nil
        }

        guard status == errSecSuccess else {
            throw DocScanError.keychainError(
                "Failed to retrieve token: \(keychainErrorMessage(status))"
            )
        }

        guard let data = result as? Data,
              let token = String(data: data, encoding: .utf8)
        else {
            throw DocScanError.keychainError("Failed to decode token data")
        }

        return token
    }

    /// Update an existing token in the Keychain (use saveToken for upsert)
    private static func updateToken(_ token: String, forAccount account: String) throws {
        guard let tokenData = token.data(using: .utf8) else {
            throw DocScanError.keychainError("Failed to encode token")
        }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account,
        ]

        let attributes: [String: Any] = [
            kSecValueData as String: tokenData,
        ]

        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        guard status == errSecSuccess else {
            throw DocScanError.keychainError(
                "Failed to update token: \(keychainErrorMessage(status))"
            )
        }
    }

    /// Delete a token from the Keychain
    public static func deleteToken(forAccount account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account,
        ]

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw DocScanError.keychainError(
                "Failed to delete token: \(keychainErrorMessage(status))"
            )
        }
    }

    /// Save (upsert) a token — stores if new, updates if existing.
    /// Uses try-store/fallback-update to avoid TOCTOU race conditions.
    /// Only falls through to update on `errSecDuplicateItem`; other store errors propagate.
    public static func saveToken(_ token: String, forAccount account: String) throws {
        let status = try storeToken(token, forAccount: account)
        if status == errSecDuplicateItem {
            try updateToken(token, forAccount: account)
        }
    }

    // MARK: - Private

    private static func keychainErrorMessage(_ status: OSStatus) -> String {
        let message = SecCopyErrorMessageString(status, nil) ?? "unknown error" as CFString
        return message as String
    }
}
