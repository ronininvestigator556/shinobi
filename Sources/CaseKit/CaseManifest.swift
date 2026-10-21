// SPDX-License-Identifier: GPL-3.0-or-later
import CryptoKit
import Foundation

/// A signed inventory of everything a case holds.
///
/// The manifest lists every artifact with its digest, so verification is a single pass over
/// declared-versus-actual, and so a recipient can check the case with `shasum` and a text
/// editor rather than with Shinobi.
///
/// **What the signature proves, and what it does not.** It proves the manifest was produced
/// by this installation and has not been altered since — so an artifact swapped or a line
/// removed after the fact is detectable. It does **not** prove the content is authentic to
/// the website it came from, and it does not prove *when* the capture happened to anyone who
/// does not already trust the investigator's clock. Those need a third party: a trusted
/// timestamp authority, which is the natural next step. Claiming more than this for a
/// self-signed manifest is the kind of overstatement that gets an exhibit excluded.
public struct CaseManifest: Codable, Equatable, Sendable {

    public struct Entry: Codable, Equatable, Sendable {
        public let visitID: Int64
        public let url: String
        public let title: String
        public let containerName: String
        public let visitedAt: String
        public let kind: String
        public let digest: String
        public let byteCount: Int
        public let note: String?
    }

    /// Bumped when the manifest's shape changes, so a verifier can refuse what it cannot read
    /// rather than silently misinterpret it.
    public let formatVersion: Int
    public let caseName: String
    public let caseReference: String?
    public let generatedAt: String
    public let tool: String
    /// Base64 Ed25519 public key. The matching private key stays in the Keychain.
    public let publicKey: String
    public let entries: [Entry]

    public static let currentFormatVersion = 1

    /// A manifest covering only the given visits, for a filtered export.
    public func selecting(visitIDs: Set<Int64>) -> CaseManifest {
        CaseManifest(
            formatVersion: formatVersion,
            caseName: caseName,
            caseReference: caseReference,
            generatedAt: generatedAt,
            tool: tool,
            publicKey: publicKey,
            entries: entries.filter { visitIDs.contains($0.visitID) }
        )
    }

    /// The exact bytes that are signed and verified.
    ///
    /// Sorted keys and a fixed date format, so the same manifest always serialises to the
    /// same bytes. Without that, a signature would verify or fail depending on dictionary
    /// ordering, which is not a property anyone wants to explain in a deposition.
    public func canonicalData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self)
    }
}

/// Where a case's signing key is kept.
///
/// Injectable because the default implementation writes to the user's login keychain, and a
/// test suite that signs a manifest would otherwise mint a real private key on every run and
/// leave it there. It did: 531 orphaned keys accumulated before this was noticed. Tests now
/// use the in-memory implementation.
public protocol CaseKeyStore: Sendable {
    func key(forCase id: String) throws -> Curve25519.Signing.PrivateKey
}

/// Ed25519 signing keys, one per case, held in the Keychain.
public struct KeychainKeyStore: CaseKeyStore {

    public static let service = "com.shinobi.browser.case-signing"

    public init() {}

    public func key(forCase id: String) throws -> Curve25519.Signing.PrivateKey {
        try CaseSigningKey.key(forCase: id)
    }
}

/// Keys that exist only for the lifetime of the process.
///
/// Signatures made with these verify exactly like any other — the public key travels in the
/// manifest — they simply cannot be reproduced after the process exits, which is correct for
/// a test and wrong for a case.
public final class EphemeralKeyStore: CaseKeyStore, @unchecked Sendable {

    private let lock = NSLock()
    private var keys: [String: Curve25519.Signing.PrivateKey] = [:]

    public init() {}

    public func key(forCase id: String) throws -> Curve25519.Signing.PrivateKey {
        lock.lock()
        defer { lock.unlock() }
        if let existing = keys[id] { return existing }
        let key = Curve25519.Signing.PrivateKey()
        keys[id] = key
        return key
    }
}

public enum CaseSigningKey {

    private static let service = KeychainKeyStore.service

    public static func key(forCase id: String) throws -> Curve25519.Signing.PrivateKey {
        if let existing = try load(id) { return existing }
        let key = Curve25519.Signing.PrivateKey()
        try store(key, forCase: id)
        return key
    }

    private static func load(_ id: String) throws -> Curve25519.Signing.PrivateKey? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: id,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return try Curve25519.Signing.PrivateKey(rawRepresentation: data)
    }

    private static func store(_ key: Curve25519.Signing.PrivateKey, forCase id: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: id,
            kSecValueData as String: key.rawRepresentation,
            // Never syncs off this machine: a signing key that reaches iCloud is a signing
            // key the investigator can no longer say was only ever in their possession.
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]
        SecItemDelete(query as CFDictionary)
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw SigningError.keychain(status) }
    }

    public enum SigningError: Error, LocalizedError {
        case keychain(OSStatus)
        case noKeyForCase

        public var errorDescription: String? {
            switch self {
            case .keychain(let status): "Could not access the case signing key (\(status))."
            case .noKeyForCase:
                "This case has no signing key on this Mac, so its manifest cannot be re-signed."
            }
        }
    }
}
