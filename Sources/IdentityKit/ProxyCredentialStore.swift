// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import Security

/// Keychain storage for proxy passwords.
///
/// Separate from `IdentityStore` on purpose. The identity list is ordinary configuration
/// that benefits from being an inspectable JSON file; a proxy password is a credential to
/// the investigator's egress infrastructure and belongs behind the platform's own
/// protection, where it is encrypted at rest and never lands in a backup of the app's
/// support directory.
public enum ProxyCredentialStore {

    private static let service = "com.shinobi.browser.proxy"

    public static func save(password: String, forContainer id: UUID) throws {
        // Delete first: SecItemUpdate on a missing item fails, and add on an existing one
        // fails with errSecDuplicateItem, so replace is the only path that is correct in
        // both directions.
        try? delete(forContainer: id)

        guard let data = password.data(using: .utf8) else { return }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: id.uuidString,
            kSecValueData as String: data,
            // The credential is only needed while the investigator is actually working, and
            // must never sync to another device.
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError.unhandled(status) }
    }

    public static func password(forContainer id: UUID) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: id.uuidString,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public static func delete(forContainer id: UUID) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: id.uuidString,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unhandled(status)
        }
    }

    public enum KeychainError: Error, LocalizedError {
        case unhandled(OSStatus)

        public var errorDescription: String? {
            switch self {
            case .unhandled(let status):
                let message = SecCopyErrorMessageString(status, nil) as String? ?? "unknown error"
                return "Keychain error \(status): \(message)"
            }
        }
    }
}
