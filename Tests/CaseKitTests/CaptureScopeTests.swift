// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import Testing

@testable import CaseKit

@Suite("Capture scope and filtered export", .serialized)
struct CaptureScopeTests {

    /// A case with one page fully captured and two only logged, which is what `manual` mode
    /// produces over a browsing session.
    private func makeMixedCase() throws -> (CaseStore, URL) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("shinobi-scope-\(UUID().uuidString)")
            .appendingPathExtension(CaseBundle.fileExtension)
        let store = try CaseStore(bundle: try CaseBundle.create(at: url), keyStore: EphemeralKeyStore())
        try store.initialise(name: "Durham", reference: nil)

        let captured = try store.record(
            url: "https://example.com/the-filing", title: "The filing",
            containerID: UUID().uuidString, containerName: "Personal",
            secure: true, text: "registered agent Jane Ashcroft")
        try store.attach(.archive, data: Data("<html>filing</html>".utf8), to: captured.id)
        try store.attach(.screenshot, data: Data(repeating: 0x89, count: 200), to: captured.id)

        for index in 1...2 {
            _ = try store.record(
                url: "https://example.com/passed-through-\(index)", title: "Passed through",
                containerID: UUID().uuidString, containerName: "Personal",
                secure: true, text: "incidental page \(index)")
        }
        return (store, url)
    }

    private func destination() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("shinobi-scope-out-\(UUID().uuidString)", isDirectory: true)
    }

    @Test("Capture modes describe themselves")
    func modesAreDescribed() {
        #expect(CaptureMode.continuous.capturesExhibitsAutomatically)
        #expect(!CaptureMode.manual.capturesExhibitsAutomatically)

        // Manual still keeps the trail: the point is to reduce what an export carries, not
        // to lose track of where the investigator went.
        #expect(CaptureMode.manual.recordsVisits)
        #expect(!CaptureMode.paused.recordsVisits)
    }

    @Test("A full export carries everything visited")
    func fullExportCarriesEverything() throws {
        let (store, caseURL) = try makeMixedCase()
        let out = destination()
        defer {
            try? FileManager.default.removeItem(at: caseURL)
            try? FileManager.default.removeItem(at: out)
        }

        let summary = try CaseExport(store: store).write(to: out)
        #expect(summary.visitCount == 3)
        #expect(summary.artifactCount == 5)      // 3 text + archive + screenshot

        let readme = try String(contentsOf: out.appendingPathComponent("README.txt"), encoding: .utf8)
        #expect(readme.contains("every page recorded in the case"))
    }

    @Test("A filtered export leaves out pages that were only logged")
    func filteredExportDropsLoggedOnlyPages() throws {
        let (store, caseURL) = try makeMixedCase()
        let out = destination()
        defer {
            try? FileManager.default.removeItem(at: caseURL)
            try? FileManager.default.removeItem(at: out)
        }

        let summary = try CaseExport(store: store, exhibitsOnly: true).write(to: out)
        #expect(summary.visitCount == 1)
        #expect(summary.artifactCount == 3)      // the captured page's text, archive, screenshot

        let manifest = try String(contentsOf: out.appendingPathComponent("manifest.json"), encoding: .utf8)
        #expect(manifest.contains("the-filing"))
        #expect(!manifest.contains("passed-through"))
    }

    @Test("A filtered export says it is a selection")
    func filteredExportDeclaresItsScope() throws {
        let (store, caseURL) = try makeMixedCase()
        let out = destination()
        defer {
            try? FileManager.default.removeItem(at: caseURL)
            try? FileManager.default.removeItem(at: out)
        }
        _ = try CaseExport(store: store, exhibitsOnly: true).write(to: out)

        // A recipient is entitled to know they are holding a selection rather than the whole
        // record — an export that quietly omits pages while reading as complete is the kind
        // of thing that discredits everything else in the bundle.
        let readme = try String(contentsOf: out.appendingPathComponent("README.txt"), encoding: .utf8)
        #expect(readme.contains("This export is a selection"))
        #expect(readme.contains("2 page(s) were visited and logged"))
        #expect(readme.contains("The full record remains in the case file"))
    }

    @Test("A filtered export verifies on its own terms")
    func filteredExportStillVerifies() throws {
        let (store, caseURL) = try makeMixedCase()
        let out = destination()
        defer {
            try? FileManager.default.removeItem(at: caseURL)
            try? FileManager.default.removeItem(at: out)
        }
        _ = try CaseExport(store: store, exhibitsOnly: true).write(to: out)

        // The filtered manifest gets its own signature. Shipping the full manifest beside a
        // subset of the artifacts would fail verification and look exactly like tampering.
        let manifestData = try Data(contentsOf: out.appendingPathComponent("manifest.json"))
        let manifest = try JSONDecoder().decode(CaseManifest.self, from: manifestData)
        let signature = try #require(Data(base64Encoded:
            try Data(contentsOf: out.appendingPathComponent("manifest.sig"))))
        let keyData = try #require(Data(base64Encoded: manifest.publicKey))
        let key = try Curve25519.Signing.PublicKey(rawRepresentation: keyData)

        #expect(key.isValidSignature(signature, for: manifestData))

        // And every checksum in the filtered bundle still matches its file.
        let sums = try String(contentsOf: out.appendingPathComponent("SHA256SUMS"), encoding: .utf8)
        for line in sums.split(separator: "\n") {
            let parts = line.components(separatedBy: "  ")
            let data = try Data(contentsOf: out.appendingPathComponent(parts[1]))
            #expect(BlobStore.digest(of: data) == parts[0], "mismatch for \(parts[1])")
        }
    }

    @Test("Capturing on request attaches to the page already logged")
    func captureOnRequestReusesTheLoggedVisit() throws {
        let (store, caseURL) = try makeMixedCase()
        defer { try? FileManager.default.removeItem(at: caseURL) }

        // A page logged in manual mode and then captured must not appear twice: one page
        // view is one visit, however many times the investigator asks for exhibits.
        let existing = try #require(try store.mostRecentVisit(for: "https://example.com/passed-through-1"))
        #expect(existing.hasExhibits == false)

        try store.attach(.archive, data: Data("<html>later</html>".utf8), to: existing.id)
        let after = try #require(try store.mostRecentVisit(for: "https://example.com/passed-through-1"))
        #expect(after.id == existing.id)
        #expect(after.hasExhibits)
        #expect(try store.visitCount() == 3)
    }
}

import CryptoKit
