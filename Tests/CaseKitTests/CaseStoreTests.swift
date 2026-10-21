// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import Testing

@testable import CaseKit

@Suite("Case store")
struct CaseStoreTests {

    private func makeStore() throws -> (CaseStore, URL) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("shinobi-case-\(UUID().uuidString)")
            .appendingPathExtension(CaseBundle.fileExtension)
        let bundle = try CaseBundle.create(at: url)
        let store = try CaseStore(bundle: bundle, keyStore: EphemeralKeyStore())
        try store.initialise(name: "Durham", reference: "2026-09-14")
        return (store, url)
    }

    @discardableResult
    private func record(
        _ store: CaseStore,
        url: String,
        title: String = "Page",
        text: String?,
        container: String = "Personal",
        at date: Date = Date()
    ) throws -> CaseStore.RecordedVisit {
        try store.record(
            url: url,
            title: title,
            containerID: UUID().uuidString,
            containerName: container,
            secure: true,
            text: text,
            visitedAt: date
        )
    }

    // MARK: Bundle

    @Test("Creating a bundle lays out the expected structure")
    func bundleLayout() throws {
        let (store, url) = try makeStore()
        defer { try? FileManager.default.removeItem(at: url) }

        // The bundle must be openable and checkable without Shinobi, so the layout is part of
        // the contract, not an implementation detail.
        #expect(FileManager.default.fileExists(atPath: store.bundle.databaseURL.path))
        #expect(FileManager.default.fileExists(atPath: store.bundle.blobsURL.path))
        #expect(FileManager.default.fileExists(atPath: store.bundle.capturesURL.path))
    }

    @Test("Creating over an existing directory is refused")
    func createRefusesExistingDirectory() throws {
        let (_, url) = try makeStore()
        defer { try? FileManager.default.removeItem(at: url) }

        // Merging into an existing directory would be a good way to mix two investigations.
        #expect(throws: CaseError.self) { _ = try CaseBundle.create(at: url) }
    }

    @Test("Case metadata round-trips")
    func metadataRoundTrips() throws {
        let (store, url) = try makeStore()
        defer { try? FileManager.default.removeItem(at: url) }

        let info = try #require(try store.info())
        #expect(info.name == "Durham")
        #expect(info.reference == "2026-09-14")
    }

    @Test("A case reopens with its contents intact")
    func caseReopens() throws {
        let (store, url) = try makeStore()
        defer { try? FileManager.default.removeItem(at: url) }
        try record(store, url: "https://example.com/a", text: "hello world")

        let reopened = try CaseStore(bundle: try CaseBundle.open(at: url), keyStore: EphemeralKeyStore())
        #expect(try reopened.visitCount() == 1)
        #expect(try reopened.info()?.name == "Durham")
    }

    // MARK: Recording

    @Test("Recording a visit stores its text as a hashed artifact")
    func recordingStoresText() throws {
        let (store, url) = try makeStore()
        defer { try? FileManager.default.removeItem(at: url) }

        let text = "The quick brown fox"
        let visit = try record(store, url: "https://example.com/", text: text)

        let digest = try #require(visit.textDigest)
        #expect(digest == BlobStore.digest(of: Data(text.utf8)))
        #expect(store.bundle.blobStore.contains(digest))
    }

    @Test("Identical page text is stored once")
    func identicalTextDeduplicates() throws {
        let (store, url) = try makeStore()
        defer { try? FileManager.default.removeItem(at: url) }

        // Refreshing a profile fifty times should not produce fifty copies.
        let first = try record(store, url: "https://example.com/a", text: "same body")
        let second = try record(store, url: "https://example.com/b", text: "same body")

        #expect(first.textDigest == second.textDigest)
        #expect(try store.visitCount() == 2)
        #expect(try store.bundle.blobStore.allDigests().count == 1)
    }

    @Test("A page with no extractable text is still recorded")
    func visitsWithoutTextAreStillRecorded() throws {
        let (store, url) = try makeStore()
        defer { try? FileManager.default.removeItem(at: url) }

        // That the investigator went somewhere is itself a fact worth keeping, even when the
        // page yielded nothing to index.
        let visit = try record(store, url: "https://example.com/pdf", text: nil)
        #expect(visit.textDigest == nil)
        #expect(try store.visitCount() == 1)
    }

    @Test("The container used is recorded with the visit")
    func containerIsRecorded() throws {
        let (store, url) = try makeStore()
        defer { try? FileManager.default.removeItem(at: url) }

        try record(store, url: "https://example.com/", text: "x", container: "Durham puppet")
        let visit = try #require(try store.recentVisits().first)
        // "Who was I browsing as" is a question an exhibit has to be able to answer.
        #expect(visit.containerName == "Durham puppet")
    }

    @Test("Visit timestamps survive the database exactly")
    func timestampsAreExact() throws {
        let (store, url) = try makeStore()
        defer { try? FileManager.default.removeItem(at: url) }

        let when = Date()
        try record(store, url: "https://example.com/", text: "x", at: when)
        let visit = try #require(try store.recentVisits().first)

        // Stored as epoch REAL rather than text: an ISO-8601 round trip does not return the
        // same Date, and ordering rapid visits depends on sub-second precision.
        #expect(visit.visited.timeIntervalSince1970 == when.timeIntervalSince1970)
    }

    // MARK: Search

    @Test("Full-text search finds a page by its body")
    func searchFindsBody() throws {
        let (store, url) = try makeStore()
        defer { try? FileManager.default.removeItem(at: url) }

        try record(store, url: "https://example.com/a", title: "Filing", text: "registered agent Jane Ashcroft")
        try record(store, url: "https://example.com/b", title: "Other", text: "nothing relevant here")

        let hits = try store.search("Ashcroft")
        #expect(hits.count == 1)
        #expect(hits.first?.url == "https://example.com/a")
        #expect(hits.first?.snippet.contains("Ashcroft") == true)
    }

    @Test("Search requires all terms")
    func searchRequiresAllTerms() throws {
        let (store, url) = try makeStore()
        defer { try? FileManager.default.removeItem(at: url) }

        try record(store, url: "https://example.com/a", text: "Jane Ashcroft Birmingham")
        try record(store, url: "https://example.com/b", text: "Jane Smith London")

        #expect(try store.search("Jane Ashcroft").count == 1)
        #expect(try store.search("Jane").count == 2)
    }

    @Test("Search folds diacritics")
    func searchFoldsDiacritics() throws {
        let (store, url) = try makeStore()
        defer { try? FileManager.default.removeItem(at: url) }

        try record(store, url: "https://example.com/", text: "contact José Müller directly")

        // Names arrive from documents, transcripts and half-remembered spellings; requiring
        // the investigator to reproduce the accents would make the index useless.
        #expect(try store.search("Jose").count == 1)
        #expect(try store.search("Muller").count == 1)
    }

    @Test("Punctuation in a query does not become an FTS syntax error", arguments: [
        "\"unbalanced", "a AND", "foo*bar", "NOT", "(", "a OR", "-", "*",
    ])
    func awkwardQueriesDoNotThrow(_ query: String) throws {
        let (store, url) = try makeStore()
        defer { try? FileManager.default.removeItem(at: url) }
        try record(store, url: "https://example.com/", text: "some body text")

        // Raw FTS5 syntax reaching the engine turns a search into an error the investigator
        // cannot interpret — it just looks like "no results".
        #expect(throws: Never.self) { _ = try store.search(query) }
    }

    @Test("An empty query returns nothing rather than everything")
    func emptyQueryReturnsNothing() throws {
        let (store, url) = try makeStore()
        defer { try? FileManager.default.removeItem(at: url) }
        try record(store, url: "https://example.com/", text: "body")

        #expect(try store.search("").isEmpty)
        #expect(try store.search("   ").isEmpty)
    }

    // MARK: Custody

    @Test("Creating a case and recording visits writes custody events")
    func custodyLogRecordsActivity() throws {
        let (store, url) = try makeStore()
        defer { try? FileManager.default.removeItem(at: url) }

        try record(store, url: "https://example.com/", text: "x")
        try store.addNote("Subject confirmed at address")

        let log = try store.custodyLog()
        let kinds = Set(log.map(\.kind))
        #expect(kinds.contains(CustodyEvent.Kind.caseCreated.rawValue))
        #expect(kinds.contains(CustodyEvent.Kind.visitRecorded.rawValue))
        #expect(kinds.contains(CustodyEvent.Kind.noteAdded.rawValue))
    }

    @Test("A visit's custody entry carries the artifact digest")
    func custodyEntryCarriesDigest() throws {
        let (store, url) = try makeStore()
        defer { try? FileManager.default.removeItem(at: url) }

        let visit = try record(store, url: "https://example.com/", text: "hello")
        let digest = try #require(visit.textDigest)
        let log = try store.custodyLog()

        #expect(log.contains { $0.detail.contains(digest) })
    }

    // MARK: Integrity

    @Test("A freshly written case verifies clean")
    func verificationPasses() throws {
        let (store, url) = try makeStore()
        defer { try? FileManager.default.removeItem(at: url) }

        for index in 0..<20 {
            try record(store, url: "https://example.com/\(index)", text: "body number \(index)")
        }

        let report = try store.verify()
        #expect(report.isClean)
        #expect(report.checked == 20)
    }

    @Test("Altering one byte of one artifact is detected and named")
    func tamperingIsDetected() throws {
        let (store, url) = try makeStore()
        defer { try? FileManager.default.removeItem(at: url) }

        for index in 0..<20 {
            try record(store, url: "https://example.com/\(index)", text: "body number \(index)")
        }
        let target = try record(store, url: "https://example.com/target", text: "the original text")
        let digest = try #require(target.textDigest)

        // This test is the product. Corrupt a single artifact and the report must name it,
        // rather than reporting a vague failure or passing.
        let path = store.bundle.blobStore.url(for: digest)
        var bytes = try Data(contentsOf: path)
        bytes[0] ^= 0x01
        try bytes.write(to: path)

        let report = try store.verify()
        #expect(!report.isClean)
        #expect(report.altered == [digest])
        #expect(report.missing.isEmpty)
    }

    @Test("A deleted artifact is reported as missing, not as intact")
    func deletionIsDetected() throws {
        let (store, url) = try makeStore()
        defer { try? FileManager.default.removeItem(at: url) }

        let visit = try record(store, url: "https://example.com/", text: "will be deleted")
        let digest = try #require(visit.textDigest)
        try FileManager.default.removeItem(at: store.bundle.blobStore.url(for: digest))

        let report = try store.verify()
        #expect(report.missing == [digest])
        #expect(!report.isClean)
    }

    @Test("Verification summaries read as English")
    func summaryPluralisation() throws {
        let (store, url) = try makeStore()
        defer { try? FileManager.default.removeItem(at: url) }

        // This string is read back in reports and quoted in correspondence, so "1 artifacts"
        // is not a cosmetic problem.
        try record(store, url: "https://example.com/1", text: "one")
        #expect(try store.verify().summary == "Verified 1 artifact, all intact")

        try record(store, url: "https://example.com/2", text: "two")
        #expect(try store.verify().summary == "Verified 2 artifacts, all intact")
    }

    @Test("A failed verification is itself written to the custody log")
    func failedVerificationIsLogged() throws {
        let (store, url) = try makeStore()
        defer { try? FileManager.default.removeItem(at: url) }

        let visit = try record(store, url: "https://example.com/", text: "text")
        let digest = try #require(visit.textDigest)
        try FileManager.default.removeItem(at: store.bundle.blobStore.url(for: digest))
        _ = try store.verify()

        // A verification that failed and left no trace would be worse than not running one.
        let log = try store.custodyLog()
        #expect(log.contains { $0.kind == CustodyEvent.Kind.verificationFailed.rawValue })
    }
}

@Suite("Transcription indexing")
struct TranscriptionIndexTests {

    private func makeStore() throws -> (CaseStore, URL) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("shinobi-ocr-\(UUID().uuidString)")
            .appendingPathExtension(CaseBundle.fileExtension)
        let store = try CaseStore(bundle: try CaseBundle.create(at: url), keyStore: EphemeralKeyStore())
        try store.initialise(name: "Durham", reference: nil)
        return (store, url)
    }

    @Test("Transcribed text becomes searchable alongside the page's own words")
    func transcriptionIsSearchable() throws {
        let (store, url) = try makeStore()
        defer { try? FileManager.default.removeItem(at: url) }

        let visit = try store.record(
            url: "https://example.com/listing", title: "Listing",
            containerID: UUID().uuidString, containerName: "Personal",
            secure: true, text: "This sentence is the page's own text.")

        // The name exists only in an image on the page.
        #expect(try store.search("Kowalczyk").isEmpty)

        try store.index(additionalText: "Kowalczyk Logistics GmbH", forVisit: visit.id)

        // That is the whole point of transcribing: a name that was only pixels stops being
        // invisible to search.
        #expect(try store.search("Kowalczyk").count == 1)
        // And the page's own words are still there.
        #expect(try store.search("sentence").count == 1)
    }

    @Test("A transcription is a separate artifact from the page text")
    func transcriptionIsItsOwnArtifact() throws {
        let (store, url) = try makeStore()
        defer { try? FileManager.default.removeItem(at: url) }

        let visit = try store.record(
            url: "https://example.com/", title: "Page",
            containerID: UUID().uuidString, containerName: "Personal",
            secure: true, text: "page words")
        try store.attach(.ocr, data: Data("pixel words".utf8), to: visit.id,
                         note: "Machine transcription of an image")

        let artifacts = try store.artifacts(forVisit: visit.id)
        let kinds = Set(artifacts.compactMap(\.artifactKind))
        // A report has to be able to tell a reading of pixels from the page's own words.
        #expect(kinds.contains(.text))
        #expect(kinds.contains(.ocr))

        let transcription = try #require(artifacts.first { $0.artifactKind == .ocr })
        #expect(transcription.note?.contains("Machine transcription") == true)
    }

    @Test("Indexing against a visit that does not exist is a no-op")
    func indexingUnknownVisitIsSafe() throws {
        let (store, url) = try makeStore()
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(throws: Never.self) { try store.index(additionalText: "x", forVisit: 999) }
    }
}
