// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import Testing

@testable import CaseKit

@Suite("Case manifest", .serialized)
struct CaseManifestTests {

    private func makeCase() throws -> (CaseStore, URL) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("shinobi-manifest-\(UUID().uuidString)")
            .appendingPathExtension(CaseBundle.fileExtension)
        let store = try CaseStore(bundle: try CaseBundle.create(at: url), keyStore: EphemeralKeyStore())
        try store.initialise(name: "Durham", reference: "2026-09-14")

        let visit = try store.record(
            url: "https://example.com/filing",
            title: "Filing",
            containerID: UUID().uuidString,
            containerName: "Durham puppet",
            secure: true,
            text: "registered agent Jane Ashcroft"
        )
        try store.attach(.archive, data: Data("<html>archive</html>".utf8), to: visit.id,
                         note: "Scripts removed")
        try store.attach(.screenshot, data: Data(repeating: 0x89, count: 512), to: visit.id)
        return (store, url)
    }

    @Test("A written manifest lists every artifact and verifies")
    func manifestVerifies() throws {
        let (store, url) = try makeCase()
        defer { try? FileManager.default.removeItem(at: url) }

        let manifest = try store.writeManifest()
        #expect(manifest.entries.count == 3)          // text, archive, screenshot
        #expect(manifest.caseName == "Durham")
        #expect(manifest.caseReference == "2026-09-14")

        let result = try store.verifyManifest()
        #expect(result.isValid)
        #expect(result.state == .valid)
    }

    @Test("The manifest is a plain file a recipient can read without Shinobi")
    func manifestIsInspectable() throws {
        let (store, url) = try makeCase()
        defer { try? FileManager.default.removeItem(at: url) }
        try store.writeManifest()

        // A recipient checking an exhibit should not have to run the tool that made it.
        let text = try String(contentsOf: store.bundle.manifestURL, encoding: .utf8)
        #expect(text.contains("\"caseName\":\"Durham\""))
        #expect(text.contains("https://example.com/filing"))
        #expect(FileManager.default.fileExists(
            atPath: store.bundle.url.appendingPathComponent("manifest.sig").path))
    }

    @Test("Editing the manifest after signing is detected")
    func tamperedManifestIsDetected() throws {
        let (store, url) = try makeCase()
        defer { try? FileManager.default.removeItem(at: url) }
        try store.writeManifest()

        // The scenario the signature exists for: someone edits the inventory — removing a
        // line, changing a URL — after the fact.
        var text = try String(contentsOf: store.bundle.manifestURL, encoding: .utf8)
        text = text.replacingOccurrences(of: "https://example.com/filing",
                                         with: "https://example.com/different")
        try text.write(to: store.bundle.manifestURL, atomically: true, encoding: .utf8)

        let result = try store.verifyManifest()
        #expect(result.state == .signatureInvalid)
        #expect(!result.isValid)
    }

    @Test("An artifact altered after signing is detected and named")
    func alteredArtifactIsDetected() throws {
        let (store, url) = try makeCase()
        defer { try? FileManager.default.removeItem(at: url) }
        let manifest = try store.writeManifest()

        let target = try #require(manifest.entries.first { $0.kind == "archive" })
        let path = store.bundle.blobStore.url(for: target.digest)
        var bytes = try Data(contentsOf: path)
        bytes[0] ^= 0x01
        try bytes.write(to: path)

        let result = try store.verifyManifest()
        // The manifest itself is untouched, so the signature still holds — what changed is
        // the evidence it points at, and the report has to say precisely that.
        #expect(result.state == .artifactsChanged)
        #expect(result.mismatched == [target.digest])
    }

    @Test("A deleted artifact is reported as missing")
    func missingArtifactIsDetected() throws {
        let (store, url) = try makeCase()
        defer { try? FileManager.default.removeItem(at: url) }
        let manifest = try store.writeManifest()

        let target = try #require(manifest.entries.first)
        try FileManager.default.removeItem(at: store.bundle.blobStore.url(for: target.digest))

        let result = try store.verifyManifest()
        #expect(result.state == .artifactsChanged)
        #expect(result.missing == [target.digest])
    }

    @Test("A case with no manifest says so rather than passing")
    func absentManifestIsNotSuccess() throws {
        let (store, url) = try makeCase()
        defer { try? FileManager.default.removeItem(at: url) }

        // "Not yet signed" must never read as "verified".
        let result = try store.verifyManifest()
        #expect(result.state == .absent)
        #expect(!result.isValid)
    }

    @Test("Signing is deterministic over the same content")
    func canonicalFormIsStable() throws {
        let (store, url) = try makeCase()
        defer { try? FileManager.default.removeItem(at: url) }

        // Signatures verify against the bytes on disk, so those bytes must not depend on
        // dictionary ordering — a signature that verifies or fails at random is not a
        // property anyone wants to explain in a deposition.
        let first = try store.writeManifest().canonicalData()
        let second = try store.writeManifest().canonicalData()

        // generatedAt legitimately differs; everything else must be byte-identical.
        func stripTimestamp(_ data: Data) -> String {
            let text = String(decoding: data, as: UTF8.self)
            return text.replacingOccurrences(
                of: #""generatedAt":"[^"]*""#, with: "", options: .regularExpression)
        }
        #expect(stripTimestamp(first) == stripTimestamp(second))
        #expect(try store.verifyManifest().isValid)
    }
}
