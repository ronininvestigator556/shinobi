// SPDX-License-Identifier: GPL-3.0-or-later
import CryptoKit
import Foundation

/// Content-addressed storage for a case's artifacts.
///
/// Every artifact is stored under the SHA-256 of its own bytes. Three properties fall out of
/// that, all of which a case file needs:
///
/// - Verification is a single pass. Re-hash each file, compare against the manifest; any
///   alteration anywhere shows up as a specific named failure rather than a vague doubt.
/// - Deduplication is automatic. Revisiting a page that has not changed costs nothing, and
///   an investigator refreshing a profile fifty times does not produce fifty copies.
/// - The name of a file cannot disagree with its contents, so there is no filing step that
///   could go wrong under pressure.
public struct BlobStore: Sendable {

    public let root: URL

    public init(root: URL) {
        self.root = root
    }

    /// Writes `data` and returns its digest.
    ///
    /// Writing an artifact that is already present is a no-op, so this is safe to call
    /// repeatedly with the same content.
    @discardableResult
    public func store(_ data: Data) throws -> String {
        let digest = Self.digest(of: data)
        let url = url(for: digest)

        guard !FileManager.default.fileExists(atPath: url.path) else { return digest }

        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        // Atomic so an interrupted write cannot leave a file whose contents do not match the
        // name it is filed under.
        try data.write(to: url, options: .atomic)
        return digest
    }

    public func data(for digest: String) throws -> Data {
        try Data(contentsOf: url(for: digest))
    }

    public func contains(_ digest: String) -> Bool {
        FileManager.default.fileExists(atPath: url(for: digest).path)
    }

    /// Fanned out by the first byte of the digest, so a case with tens of thousands of
    /// artifacts does not put them all in one directory.
    public func url(for digest: String) -> URL {
        root
            .appendingPathComponent(String(digest.prefix(2)), isDirectory: true)
            .appendingPathComponent(digest)
    }

    /// Re-hashes a stored artifact and reports whether it still matches the name it is filed
    /// under. This is the primitive the whole integrity story rests on.
    public func verify(_ digest: String) -> VerificationResult {
        let url = url(for: digest)
        guard let data = try? Data(contentsOf: url) else { return .missing }
        let actual = Self.digest(of: data)
        return actual == digest ? .intact : .altered(actual: actual)
    }

    public enum VerificationResult: Equatable, Sendable {
        case intact
        case missing
        case altered(actual: String)
    }

    public static func digest(of data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// Every digest currently stored, for a full verification pass.
    public func allDigests() throws -> [String] {
        guard FileManager.default.fileExists(atPath: root.path) else { return [] }
        let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey])
        var digests: [String] = []
        while let url = enumerator?.nextObject() as? URL {
            guard (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true else { continue }
            digests.append(url.lastPathComponent)
        }
        return digests
    }
}
