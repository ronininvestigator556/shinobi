// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import Testing

@testable import CaseKit

@Suite("Export and WARC", .serialized)
struct ExportTests {

    private func makeCase() throws -> (CaseStore, URL) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("shinobi-export-\(UUID().uuidString)")
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
        try store.attach(.archive, data: Data("<html><body>archive</body></html>".utf8),
                         to: visit.id, note: "1 image could not be inlined")
        try store.attach(.screenshot, data: Data(repeating: 0x89, count: 300), to: visit.id)
        return (store, url)
    }

    private func destination() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("shinobi-out-\(UUID().uuidString)", isDirectory: true)
    }

    // MARK: Export shape

    @Test("An export contains everything needed to check it without Shinobi")
    func exportIsSelfContained() throws {
        let (store, caseURL) = try makeCase()
        let out = destination()
        defer {
            try? FileManager.default.removeItem(at: caseURL)
            try? FileManager.default.removeItem(at: out)
        }

        let summary = try CaseExport(store: store).write(to: out)
        #expect(summary.artifactCount == 3)
        #expect(summary.visitCount == 1)

        for name in ["manifest.json", "manifest.sig", "public-key.pem", "SHA256SUMS",
                     "README.txt", "Durham.warc"] {
            #expect(FileManager.default.fileExists(atPath: out.appendingPathComponent(name).path),
                    "missing \(name)")
        }
    }

    @Test("SHA256SUMS is in the exact format shasum reads")
    func checksumsAreStandardFormat() throws {
        let (store, caseURL) = try makeCase()
        let out = destination()
        defer {
            try? FileManager.default.removeItem(at: caseURL)
            try? FileManager.default.removeItem(at: out)
        }
        _ = try CaseExport(store: store).write(to: out)

        let text = try String(contentsOf: out.appendingPathComponent("SHA256SUMS"), encoding: .utf8)
        for line in text.split(separator: "\n") {
            // "<64 hex>  <path>" — two spaces, which is what the tool expects.
            let parts = line.components(separatedBy: "  ")
            #expect(parts.count == 2, "malformed line: \(line)")
            #expect(parts[0].count == 64)
            let isHex = parts[0].allSatisfy(\.isHexDigit)
            #expect(isHex)
        }
    }

    @Test("Every declared checksum matches the exported file")
    func checksumsAreCorrect() throws {
        let (store, caseURL) = try makeCase()
        let out = destination()
        defer {
            try? FileManager.default.removeItem(at: caseURL)
            try? FileManager.default.removeItem(at: out)
        }
        _ = try CaseExport(store: store).write(to: out)

        let text = try String(contentsOf: out.appendingPathComponent("SHA256SUMS"), encoding: .utf8)
        for line in text.split(separator: "\n") {
            let parts = line.components(separatedBy: "  ")
            let data = try Data(contentsOf: out.appendingPathComponent(parts[1]))
            #expect(BlobStore.digest(of: data) == parts[0], "checksum mismatch for \(parts[1])")
        }
    }

    @Test("The public key is a PEM openssl can read")
    func publicKeyIsPEM() throws {
        let (store, caseURL) = try makeCase()
        let out = destination()
        defer {
            try? FileManager.default.removeItem(at: caseURL)
            try? FileManager.default.removeItem(at: out)
        }
        _ = try CaseExport(store: store).write(to: out)

        let pem = try String(contentsOf: out.appendingPathComponent("public-key.pem"), encoding: .utf8)
        #expect(pem.hasPrefix("-----BEGIN PUBLIC KEY-----"))
        #expect(pem.contains("-----END PUBLIC KEY-----"))
        // 12-byte SubjectPublicKeyInfo prefix plus the 32-byte raw key.
        let body = pem.replacingOccurrences(of: "-----BEGIN PUBLIC KEY-----", with: "")
            .replacingOccurrences(of: "-----END PUBLIC KEY-----", with: "")
            .replacingOccurrences(of: "\n", with: "")
        #expect(Data(base64Encoded: body)?.count == 44)
    }

    @Test("Exporting refuses to overwrite")
    func exportDoesNotOverwrite() throws {
        let (store, caseURL) = try makeCase()
        let out = destination()
        defer {
            try? FileManager.default.removeItem(at: caseURL)
            try? FileManager.default.removeItem(at: out)
        }
        _ = try CaseExport(store: store).write(to: out)

        // An export may already have been sent to someone; replacing it silently is not
        // something the sender could undo or even notice.
        #expect(throws: CaseError.self) { _ = try CaseExport(store: store).write(to: out) }
    }

    @Test("Fidelity notes travel with the export")
    func notesAreExported() throws {
        let (store, caseURL) = try makeCase()
        let out = destination()
        defer {
            try? FileManager.default.removeItem(at: caseURL)
            try? FileManager.default.removeItem(at: out)
        }
        _ = try CaseExport(store: store).write(to: out)

        // A recipient must be able to see where a capture was incomplete without asking.
        let manifest = try String(contentsOf: out.appendingPathComponent("manifest.json"), encoding: .utf8)
        #expect(manifest.contains("1 image could not be inlined"))

        // Decoded leniently: a WARC carries binary payloads (PNG, PDF) and is not valid
        // UTF-8 as a whole.
        let warcData = try Data(contentsOf: out.appendingPathComponent("Durham.warc"))
        let warc = String(decoding: warcData, as: UTF8.self)
        #expect(warc.contains("note: 1 image could not be inlined"))
    }

    @Test("The verification instructions are ones that actually run")
    func readmeInstructionsAreCorrect() throws {
        let (store, caseURL) = try makeCase()
        let out = destination()
        defer {
            try? FileManager.default.removeItem(at: caseURL)
            try? FileManager.default.removeItem(at: out)
        }
        _ = try CaseExport(store: store).write(to: out)

        let readme = try String(contentsOf: out.appendingPathComponent("README.txt"), encoding: .utf8)

        // A wrong instruction here is worse than a code bug: it makes a valid exhibit look
        // tampered to the person checking it. The first version said
        // `base64 -d manifest.sig`, which macOS's base64 rejects outright — the decode
        // produced nothing and the signature "failed".
        #expect(readme.contains("base64 -d < manifest.sig"))
        #expect(!readme.contains("base64 -d manifest.sig"))

        // And openssl's own decoder needs -A, because the signature is one unwrapped line.
        #expect(!readme.contains("openssl base64 -d -in"))

        #expect(readme.contains("shasum -a 256 -c SHA256SUMS"))
        #expect(readme.contains("openssl pkeyutl -verify"))
    }

    // MARK: WARC

    @Test("The WARC is structurally valid")
    func warcIsWellFormed() throws {
        let (store, caseURL) = try makeCase()
        let out = destination()
        defer {
            try? FileManager.default.removeItem(at: caseURL)
            try? FileManager.default.removeItem(at: out)
        }
        _ = try CaseExport(store: store).write(to: out)

        let data = try Data(contentsOf: out.appendingPathComponent("Durham.warc"))
        let text = String(decoding: data, as: UTF8.self)

        #expect(text.hasPrefix("WARC/1.1\r\n"))
        #expect(text.contains("WARC-Type: warcinfo"))
        #expect(text.contains("WARC-Type: resource"))
        #expect(text.contains("WARC-Target-URI: https://example.com/filing"))
        #expect(text.contains("WARC-Block-Digest: sha256:"))

        // Records that claim to be responses would assert they carry the server's own
        // headers. Shinobi reconstructs from the rendered page and cannot honestly say that.
        #expect(!text.contains("WARC-Type: response"))
    }

    @Test("Every WARC Content-Length matches its block")
    func warcContentLengthsAreCorrect() throws {
        let (store, caseURL) = try makeCase()
        let out = destination()
        defer {
            try? FileManager.default.removeItem(at: caseURL)
            try? FileManager.default.removeItem(at: out)
        }
        _ = try CaseExport(store: store).write(to: out)

        // A wrong Content-Length desynchronises every following record, so a reader would
        // either fail or, worse, silently misattribute content.
        let data = try Data(contentsOf: out.appendingPathComponent("Durham.warc"))
        var offset = 0
        var records = 0
        let separator = Array("\r\n\r\n".utf8)
        let bytes = [UInt8](data)

        while offset < bytes.count {
            guard let headerEnd = findRange(of: separator, in: bytes, from: offset) else { break }
            let header = String(decoding: bytes[offset..<headerEnd.lowerBound], as: UTF8.self)
            guard let lengthLine = header.split(separator: "\r\n").first(where: {
                $0.hasPrefix("Content-Length:")
            }), let declared = Int(lengthLine.dropFirst("Content-Length:".count).trimmingCharacters(in: .whitespaces))
            else { break }

            let blockStart = headerEnd.upperBound
            #expect(blockStart + declared <= bytes.count, "record \(records) runs past end of file")
            offset = blockStart + declared + 4     // block plus the two trailing CRLFs
            records += 1
        }

        // Derived rather than hardcoded: one warcinfo, one resource per artifact, and one
        // metadata record for each artifact carrying a fidelity note. Hardcoding this hid a
        // correct change — the page-text artifact gained a note and the count moved.
        let manifestText = try String(contentsOf: out.appendingPathComponent("manifest.json"), encoding: .utf8)
        let manifest = try JSONDecoder().decode(CaseManifest.self, from: Data(manifestText.utf8))
        let expected = 1 + manifest.entries.count + manifest.entries.filter { $0.note != nil }.count
        #expect(records == expected, "parsed \(records) records, expected \(expected)")
        #expect(offset == bytes.count, "trailing bytes after the final record")
    }

    private func findRange(of pattern: [UInt8], in bytes: [UInt8], from: Int) -> Range<Int>? {
        guard pattern.count <= bytes.count else { return nil }
        var index = from
        while index <= bytes.count - pattern.count {
            if Array(bytes[index..<index + pattern.count]) == pattern {
                return index..<(index + pattern.count)
            }
            index += 1
        }
        return nil
    }
}
