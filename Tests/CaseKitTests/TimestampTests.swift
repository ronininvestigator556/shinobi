// SPDX-License-Identifier: GPL-3.0-or-later
import CryptoKit
import Foundation
import Testing

@testable import CaseKit

@Suite("RFC 3161 timestamping")
struct TimestampTests {

    @Test("The request carries the payload's SHA-256 and nothing else")
    func requestCarriesOnlyTheHash() throws {
        let payload = Data("a manifest naming a subject and every page visited".utf8)
        let request = TimestampClient.request(for: payload)

        // The privacy property that makes timestamping usable at all: the authority learns a
        // hash, not the investigation. Asserted by checking the payload cannot be found in
        // what is sent.
        let expected = Data(SHA256.hash(data: payload))
        #expect(request.range(of: expected) != nil)
        #expect(request.range(of: payload) == nil)
        #expect(request.count < 128)
    }

    @Test("The request is well-formed DER")
    func requestIsWellFormedDER() throws {
        let request = TimestampClient.request(
            for: Data("x".utf8), nonce: Data([1, 2, 3, 4, 5, 6, 7, 8]))

        let outer = try #require(DER.element(in: request, at: 0))
        #expect(outer.tag == 0x30)                       // SEQUENCE
        #expect(outer.end == request.count)              // nothing trailing

        let version = try #require(DER.element(in: outer.body, at: 0))
        #expect(version.tag == 0x02)
        #expect(version.body == Data([0x01]))            // v1
    }

    @Test("Long lengths encode in the long form")
    func lengthEncoding() {
        #expect(DER.length(5) == Data([0x05]))
        #expect(DER.length(127) == Data([0x7F]))
        // 128 and above must switch to long form, or every large request is malformed.
        #expect(DER.length(128) == Data([0x81, 0x80]))
        #expect(DER.length(300) == Data([0x82, 0x01, 0x2C]))
    }

    @Test("Integers that would read as negative get a leading zero")
    func integerPadding() {
        // Without the pad, a nonce whose first byte has the high bit set becomes a negative
        // integer and the authority rejects the request.
        let padded = DER.integer(bytes: Data([0xFF, 0x01]))
        #expect(padded == Data([0x02, 0x03, 0x00, 0xFF, 0x01]))
    }

    @Test("A rejection is not mistaken for a timestamp")
    func rejectionIsDetected() throws {
        // status 2 is "rejection". A refusal is still a well-formed HTTP 200 body, and
        // storing one as manifest.tsr would put a file in an export that proves nothing.
        let statusInfo = DER.sequence([DER.integer(2)])
        let response = DER.sequence([statusInfo])

        #expect(throws: TimestampClient.TimestampError.self) {
            try TimestampClient.checkGranted(response)
        }
    }

    @Test("A granted status with no token is refused")
    func missingTokenIsDetected() throws {
        // Would otherwise pass the status check and still be useless.
        let response = DER.sequence([DER.sequence([DER.integer(0)])])
        #expect(throws: TimestampClient.TimestampError.noToken) {
            try TimestampClient.checkGranted(response)
        }
    }

    @Test("A granted status with a token is accepted")
    func grantedIsAccepted() throws {
        let response = DER.sequence([
            DER.sequence([DER.integer(0)]),
            DER.octetString(Data(repeating: 0xAB, count: 32)),
        ])
        #expect(throws: Never.self) { try TimestampClient.checkGranted(response) }
    }

    @Test("Garbage is refused rather than stored")
    func malformedIsDetected() {
        #expect(throws: TimestampClient.TimestampError.self) {
            try TimestampClient.checkGranted(Data([0x00, 0x01, 0x02]))
        }
    }
}

@Suite("Timestamped exports", .serialized)
struct TimestampedExportTests {

    private func makeCase() throws -> (CaseStore, URL) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("shinobi-ts-\(UUID().uuidString)")
            .appendingPathExtension(CaseBundle.fileExtension)
        let store = try CaseStore(bundle: try CaseBundle.create(at: url), keyStore: EphemeralKeyStore())
        try store.initialise(name: "Durham", reference: nil)
        let visit = try store.record(
            url: "https://example.com/a", title: "A",
            containerID: UUID().uuidString, containerName: "Personal",
            secure: true, text: "body")
        try store.attach(.archive, data: Data("<html>a</html>".utf8), to: visit.id)
        return (store, url)
    }

    @Test("Exporting an unchanged case leaves the signed manifest byte-identical")
    func exportDoesNotDisturbTheManifest() throws {
        let (store, caseURL) = try makeCase()
        let out = FileManager.default.temporaryDirectory
            .appendingPathComponent("shinobi-ts-out-\(UUID().uuidString)", isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: caseURL)
            try? FileManager.default.removeItem(at: out)
        }

        try store.writeManifest()
        let before = try Data(contentsOf: store.bundle.manifestURL)

        _ = try CaseExport(store: store).write(to: out)
        let after = try Data(contentsOf: store.bundle.manifestURL)

        // The defect this guards: export rewrote the manifest with a fresh generatedAt, so any
        // RFC 3161 token taken over the previous bytes silently stopped covering the file
        // being shipped — valid evidence made to look invalid.
        #expect(before == after)
        let exported = try Data(contentsOf: out.appendingPathComponent("manifest.json"))
        #expect(exported == before)
    }

    @Test("A stale timestamp is discarded rather than shipped")
    func staleTimestampIsNotShipped() throws {
        let (store, caseURL) = try makeCase()
        let out = FileManager.default.temporaryDirectory
            .appendingPathComponent("shinobi-ts-out-\(UUID().uuidString)", isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: caseURL)
            try? FileManager.default.removeItem(at: out)
        }

        try store.writeManifest()
        try Data("pretend token".utf8).write(to: store.bundle.timestampURL)

        // Capturing more evidence invalidates a token taken over the older manifest.
        let visit = try store.record(
            url: "https://example.com/b", title: "B",
            containerID: UUID().uuidString, containerName: "Personal",
            secure: true, text: "more")
        try store.attach(.screenshot, data: Data([0x89]), to: visit.id)

        _ = try CaseExport(store: store).write(to: out)

        // A token that does not cover the manifest beside it reads as tampering rather than
        // as staleness, so it must not travel.
        #expect(!FileManager.default.fileExists(
            atPath: out.appendingPathComponent("manifest.tsr").path))
        let readme = try String(contentsOf: out.appendingPathComponent("README.txt"), encoding: .utf8)
        #expect(readme.contains("no such timestamp accompanies this export"))
    }

    @Test("Rewriting the manifest drops a timestamp that no longer covers it")
    func rewritingClearsTheToken() throws {
        let (store, caseURL) = try makeCase()
        defer { try? FileManager.default.removeItem(at: caseURL) }

        try store.writeManifest()
        try Data("token".utf8).write(to: store.bundle.timestampURL)
        #expect(store.hasTimestamp)

        try store.writeManifest()
        #expect(!store.hasTimestamp)
    }
}
