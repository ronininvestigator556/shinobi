// SPDX-License-Identifier: GPL-3.0-or-later
import CryptoKit
import Foundation
import GRDB
import ShinobiKit

/// The index inside a `.shinobicase` bundle.
public final class CaseStore: @unchecked Sendable {

    public let bundle: CaseBundle
    private let queue: DatabaseQueue
    private let blobs: BlobStore
    private let keyStore: CaseKeyStore

    public init(bundle: CaseBundle, keyStore: CaseKeyStore = KeychainKeyStore()) throws {
        self.bundle = bundle
        self.blobs = bundle.blobStore
        self.keyStore = keyStore

        var configuration = Configuration()
        // A case file is evidence; a corrupted index from a hard shutdown is not acceptable.
        configuration.prepareDatabase { db in
            try db.execute(sql: "PRAGMA journal_mode = WAL")
            try db.execute(sql: "PRAGMA synchronous = FULL")
            try db.execute(sql: "PRAGMA foreign_keys = ON")
        }

        self.queue = try DatabaseQueue(path: bundle.databaseURL.path, configuration: configuration)
        try Self.migrator.migrate(queue)
    }

    // MARK: Schema

    /// Migrations are append-only and named, so an older Shinobi opening a newer case fails
    /// loudly rather than reading it wrong.
    static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("v1") { db in
            try db.create(table: "caseInfo") { t in
                t.primaryKey("id", .integer)
                t.column("name", .text).notNull()
                t.column("reference", .text)
                t.column("createdAt", .double).notNull()
                t.column("openedAt", .double).notNull()
            }

            try db.create(table: "visit") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("url", .text).notNull()
                t.column("host", .text)
                t.column("title", .text).notNull()
                t.column("containerID", .text).notNull()
                t.column("containerName", .text).notNull()
                t.column("visitedAt", .double).notNull()
                t.column("textDigest", .text)
                t.column("textLength", .integer)
                t.column("secure", .boolean).notNull()
            }
            try db.create(index: "visit_visitedAt", on: "visit", columns: ["visitedAt"])
            try db.create(index: "visit_host", on: "visit", columns: ["host"])
            try db.create(index: "visit_url", on: "visit", columns: ["url"])

            try db.create(table: "note") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("body", .text).notNull()
                t.column("createdAt", .double).notNull()
                t.column("visitID", .integer).references("visit", onDelete: .setNull)
            }

            try db.create(table: "custodyEvent") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("kind", .text).notNull()
                t.column("detail", .text).notNull()
                t.column("occurredAt", .double).notNull()
            }

            // A standalone FTS5 table rather than an external-content one. The canonical
            // copy of a page's text is the hashed blob on disk; this index is explicitly
            // derived from it and can be rebuilt, which is why it is allowed to hold its own
            // copy of the text.
            try db.create(virtualTable: "visitSearch", using: FTS5()) { t in
                t.column("url")
                t.column("title")
                t.column("body")
                // Diacritic folding is not cosmetic here: an investigator who types
                // "Jose" must find "José", and one who types "Muller" must find "Müller".
                // Names arrive from documents, transcripts and half-remembered spellings.
                t.tokenizer = .unicode61(diacritics: .removeLegacy)
            }
        }

        migrator.registerMigration("v2-artifacts") { db in
            try db.create(table: "artifact") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("visitID", .integer).notNull().references("visit", onDelete: .cascade)
                t.column("kind", .text).notNull()
                t.column("digest", .text).notNull()
                t.column("byteCount", .integer).notNull()
                t.column("createdAt", .double).notNull()
                t.column("note", .text)
            }
            try db.create(index: "artifact_visit", on: "artifact", columns: ["visitID"])
            try db.create(index: "artifact_digest", on: "artifact", columns: ["digest"])

            // Carry forward the text digests recorded before artifacts existed, so a case
            // made with an earlier build verifies identically under the new schema.
            try db.execute(sql: """
                INSERT INTO artifact (visitID, kind, digest, byteCount, createdAt)
                SELECT id, 'text', textDigest, COALESCE(textLength, 0), visitedAt
                FROM visit WHERE textDigest IS NOT NULL
                """)
        }

        return migrator
    }

    // MARK: Case metadata

    public func initialise(name: String, reference: String?) throws {
        try queue.write { db in
            try CaseInfo(name: name, reference: reference).insert(db)
            var event = CustodyEvent(kind: .caseCreated, detail: "Case '\(name)' created")
            try event.insert(db)
        }
    }

    public func info() throws -> CaseInfo? {
        try queue.read { try CaseInfo.fetchOne($0) }
    }

    public func recordOpened() throws {
        try queue.write { db in
            var event = CustodyEvent(kind: .caseOpened, detail: "Case opened")
            try event.insert(db)
        }
    }

    // MARK: Visits

    /// Records a page the investigator looked at, storing its text as a hashed artifact.
    ///
    /// Returns the digest of the stored text so the interface can show it. The text is
    /// written to the blob store *before* the row is inserted: a row pointing at a missing
    /// artifact would be a worse failure than an artifact with no row, which verification
    /// can simply report as unreferenced.
    @discardableResult
    public func record(
        url: String,
        title: String,
        containerID: String,
        containerName: String,
        secure: Bool,
        text: String?,
        visitedAt: Date = Date()
    ) throws -> RecordedVisit {
        var digest: String?
        var length: Int?

        if let text, !text.isEmpty {
            let data = Data(text.utf8)
            digest = try blobs.store(data)
            // Bytes, not characters: the manifest declares artifact sizes, and a recipient
            // checking one against `ls -l` should not find a discrepancy on any page
            // containing a non-ASCII character.
            length = data.count
        }

        var visit = Visit(
            url: url,
            title: title,
            containerID: containerID,
            containerName: containerName,
            secure: secure,
            visitedAt: visitedAt,
            textDigest: digest,
            textLength: length
        )

        try queue.write { db in
            try visit.insert(db)

            // The text is an artifact like any other, and must appear in the manifest as one.
            // It previously existed only as `visit.textDigest`, which meant the manifest — the
            // document a recipient actually checks — silently omitted the page text.
            if let id = visit.id, let digest, let length {
                var artifact = Artifact(
                    visitID: id,
                    kind: .text,
                    digest: digest,
                    byteCount: length,
                    note: "As rendered; content hidden at capture time is not included",
                    createdAt: visitedAt
                )
                try artifact.insert(db)
            }

            if let id = visit.id {
                try db.execute(
                    sql: "INSERT INTO visitSearch(rowid, url, title, body) VALUES (?, ?, ?, ?)",
                    arguments: [id, url, title, text ?? ""]
                )
            }
            var event = CustodyEvent(
                kind: .visitRecorded,
                detail: digest.map { "\(url) text sha256:\($0)" } ?? url,
                occurredAt: visitedAt
            )
            try event.insert(db)
        }

        return RecordedVisit(id: visit.id ?? 0, textDigest: digest, textLength: length)
    }

    public struct RecordedVisit: Sendable, Equatable {
        public let id: Int64
        public let textDigest: String?
        public let textLength: Int?
    }

    /// Attaches an artifact to a visit, storing the bytes and recording the digest.
    ///
    /// The bytes are written before the row, so a row can never point at an artifact that is
    /// not there. The reverse — an artifact with no row — is recoverable, and verification
    /// reports it as unreferenced rather than treating it as a failure.
    @discardableResult
    public func attach(
        _ kind: Artifact.Kind,
        data: Data,
        to visitID: Int64,
        note: String? = nil
    ) throws -> Artifact {
        let digest = try blobs.store(data)
        var artifact = Artifact(
            visitID: visitID,
            kind: kind,
            digest: digest,
            byteCount: data.count,
            note: note
        )
        try queue.write { db in
            try artifact.insert(db)
            var event = CustodyEvent(
                kind: .visitRecorded,
                detail: "\(kind.displayName) sha256:\(digest)" + (note.map { " (\($0))" } ?? "")
            )
            try event.insert(db)
        }
        return artifact
    }

    /// Adds text to a visit's search index without creating a second visit.
    ///
    /// Used for transcriptions: a screenshot's words are only findable if they reach the
    /// index, and the whole value of transcribing is that a name appearing solely in an image
    /// stops being invisible to search.
    public func index(additionalText text: String, forVisit visitID: Int64) throws {
        guard !text.isEmpty else { return }
        try queue.write { db in
            guard let existing = try Row.fetchOne(
                db, sql: "SELECT body FROM visitSearch WHERE rowid = ?", arguments: [visitID])
            else { return }
            let body: String = existing["body"] ?? ""
            try db.execute(
                sql: "UPDATE visitSearch SET body = ? WHERE rowid = ?",
                arguments: [body + "\n" + text, visitID])
        }
    }

    public func artifacts(forVisit visitID: Int64) throws -> [Artifact] {
        try queue.read { db in
            try Artifact.filter(Column("visitID") == visitID).order(Column("id")).fetchAll(db)
        }
    }

    public func artifactCount() throws -> Int {
        try queue.read { try Artifact.fetchCount($0) }
    }

    public func visitCount() throws -> Int {
        try queue.read { try Visit.fetchCount($0) }
    }

    public func recentVisits(limit: Int = 200) throws -> [Visit] {
        try queue.read { db in
            try Visit.order(Column("visitedAt").desc).limit(limit).fetchAll(db)
        }
    }

    /// The most recent visit for a URL, and whether it already carries exhibits beyond text.
    ///
    /// Used so that capturing on request attaches to the page view that was just logged,
    /// rather than recording the same page view twice.
    public func mostRecentVisit(for url: String) throws -> (id: Int64, hasExhibits: Bool)? {
        try queue.read { db in
            guard let row = try Row.fetchOne(db, sql: """
                SELECT v.id AS id,
                       (SELECT COUNT(*) FROM artifact a
                        WHERE a.visitID = v.id AND a.kind <> 'text') AS exhibits
                FROM visit v WHERE v.url = ? ORDER BY v.visitedAt DESC LIMIT 1
                """, arguments: [url]) else { return nil }
            let exhibits: Int = row["exhibits"]
            return (row["id"], exhibits > 0)
        }
    }

    // MARK: Search

    /// Full-text search across everything recorded in this case.
    public func search(_ query: String, limit: Int = 100) throws -> [SearchHit] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        // Parse into an FTS5 expression rather than passing raw input through. A stray
        // quote or operator would otherwise turn a search into a syntax error, and the
        // investigator would have no idea why their query "found nothing".
        guard let pattern = FTS5Pattern(matchingAllTokensIn: trimmed) else { return [] }

        return try queue.read { db in
            try SearchHit.fetchAll(db, sql: """
                SELECT
                    v.id                              AS visitID,
                    v.url                             AS url,
                    v.title                           AS title,
                    v.containerName                   AS containerName,
                    v.visitedAt                       AS visitedAt,
                    snippet(visitSearch, 2, '⟦', '⟧', '…', 12) AS snippet
                FROM visitSearch
                JOIN visit v ON v.id = visitSearch.rowid
                WHERE visitSearch MATCH ?
                ORDER BY bm25(visitSearch, 2.0, 8.0, 1.0)
                LIMIT ?
                """, arguments: [pattern, limit])
        }
    }

    // MARK: Notes

    @discardableResult
    public func addNote(_ body: String, visitID: Int64? = nil) throws -> Note {
        var note = Note(body: body, visitID: visitID)
        try queue.write { db in
            try note.insert(db)
            var event = CustodyEvent(kind: .noteAdded, detail: "Note added")
            try event.insert(db)
        }
        return note
    }

    public func notes(limit: Int = 200) throws -> [Note] {
        try queue.read { db in
            try Note.order(Column("createdAt").desc).limit(limit).fetchAll(db)
        }
    }

    // MARK: Custody

    public func custodyLog(limit: Int = 500) throws -> [CustodyEvent] {
        try queue.read { db in
            try CustodyEvent.order(Column("occurredAt").desc).limit(limit).fetchAll(db)
        }
    }

    // MARK: Manifest

    /// Builds and signs a manifest of everything the case holds.
    ///
    /// Written next to the database as `manifest.json` and `manifest.sig`, both plain files,
    /// so a recipient can verify the case with `shasum` and any Ed25519 implementation rather
    /// than needing Shinobi.
    @discardableResult
    public func writeManifest() throws -> CaseManifest {
        let key = try keyStore.key(forCase: bundle.displayName)
        let manifest = try buildManifest(
            publicKey: key.publicKey.rawRepresentation.base64EncodedString(),
            generatedAt: Date().roundedToPersistedPrecision()
                .formatted(Date.ISO8601FormatStyle.shinobiTimestamp)
        )

        let canonical = try manifest.canonicalData()
        let signature = try key.signature(for: canonical)

        try canonical.write(to: bundle.manifestURL, options: .atomic)
        try signature.base64EncodedData().write(to: bundle.signatureURL, options: .atomic)

        // A timestamp taken over the previous manifest no longer covers this one, and a token
        // that does not cover the file beside it reads as tampering rather than as staleness.
        try? FileManager.default.removeItem(at: bundle.timestampURL)

        let count = manifest.entries.count
        try queue.write { db in
            var event = CustodyEvent(
                kind: .verificationRun,
                detail: "Manifest written and signed over \(count) artifact(s)"
            )
            try event.insert(db)
        }

        return manifest
    }

    /// Assembles a manifest from the current contents of the case.
    ///
    /// Separated from writing so the same construction can be compared against what is
    /// already on disk without disturbing it.
    func buildManifest(publicKey: String, generatedAt: String) throws -> CaseManifest {
        let info = try self.info()
        let rows: [CaseManifest.Entry] = try queue.read { db in
            try Row.fetchAll(db, sql: """
                SELECT v.id AS visitID, v.url, v.title, v.containerName, v.visitedAt,
                       a.kind, a.digest, a.byteCount, a.note
                FROM artifact a
                JOIN visit v ON v.id = a.visitID
                ORDER BY a.id
                """).map { row in
                CaseManifest.Entry(
                    visitID: row["visitID"],
                    url: row["url"],
                    title: row["title"],
                    containerName: row["containerName"],
                    visitedAt: Date(timeIntervalSince1970: row["visitedAt"])
                        .formatted(Date.ISO8601FormatStyle.shinobiTimestamp),
                    kind: row["kind"],
                    digest: row["digest"],
                    byteCount: row["byteCount"],
                    note: row["note"]
                )
            }
        }

        return CaseManifest(
            formatVersion: CaseManifest.currentFormatVersion,
            caseName: info?.name ?? bundle.displayName,
            caseReference: info?.reference,
            generatedAt: generatedAt,
            tool: "Shinobi",
            publicKey: publicKey,
            entries: rows
        )
    }

    /// The manifest on disk when it still describes the case exactly, or a freshly written
    /// one when it does not.
    ///
    /// Exists so that exporting an unchanged case does not disturb bytes that something else
    /// — a signature, a timestamp — has already been taken over.
    public func manifestMatchingDiskOrRewritten() throws -> CaseManifest {
        guard let data = try? Data(contentsOf: bundle.manifestURL),
              let existing = try? JSONDecoder().decode(CaseManifest.self, from: data)
        else { return try writeManifest() }

        // Compare everything except when it was generated: the entries are what describe the
        // case, and `generatedAt` differs on every write by construction.
        let current = try buildManifest(publicKey: existing.publicKey, generatedAt: existing.generatedAt)
        return current == existing ? existing : try writeManifest()
    }

    /// Asks an independent authority to attest that the current manifest existed now.
    ///
    /// This is the one step that makes the case file say *when* rather than only *what*. The
    /// authority receives a SHA-256 hash and nothing else — not the manifest, not the case,
    /// nothing about the subject — so proving the timing does not disclose the investigation.
    ///
    /// Any existing timestamp is replaced only after a new one has been obtained, so a failed
    /// request cannot leave a case worse off than it started.
    @discardableResult
    public func timestampManifest(using client: TimestampClient = TimestampClient()) async throws -> Date {
        if !FileManager.default.fileExists(atPath: bundle.manifestURL.path) {
            _ = try writeManifest()
        }
        let manifestData = try Data(contentsOf: bundle.manifestURL)
        let response = try await client.timestamp(manifestData)
        try response.write(to: bundle.timestampURL, options: .atomic)

        let now = Date().roundedToPersistedPrecision()
        let authority = client.authority.host ?? client.authority.absoluteString
        try await queue.write { db in
            var event = CustodyEvent(
                kind: .verificationRun,
                detail: "Manifest timestamped by \(authority)"
            )
            try event.insert(db)
        }
        return now
    }

    public var hasTimestamp: Bool {
        FileManager.default.fileExists(atPath: bundle.timestampURL.path)
    }

    /// Signs arbitrary manifest bytes with this case's key, for filtered exports.
    public func sign(_ data: Data) throws -> Data {
        try keyStore.key(forCase: bundle.displayName).signature(for: data)
    }

    /// Checks the manifest's signature and that every artifact it declares still matches.
    public func verifyManifest() throws -> ManifestVerification {
        guard let manifestData = try? Data(contentsOf: bundle.manifestURL),
              let signatureText = try? Data(contentsOf: bundle.url.appendingPathComponent("manifest.sig")),
              let signature = Data(base64Encoded: signatureText)
        else { return ManifestVerification(state: .absent, mismatched: [], missing: []) }

        let manifest = try JSONDecoder().decode(CaseManifest.self, from: manifestData)

        guard let keyData = Data(base64Encoded: manifest.publicKey),
              let publicKey = try? Curve25519.Signing.PublicKey(rawRepresentation: keyData)
        else { return ManifestVerification(state: .unreadable, mismatched: [], missing: []) }

        // The signature is checked against the file exactly as it sits on disk, not against a
        // freshly re-encoded manifest — otherwise an encoder change would silently "repair" a
        // tampered file.
        guard publicKey.isValidSignature(signature, for: manifestData) else {
            return ManifestVerification(state: .signatureInvalid, mismatched: [], missing: [])
        }

        var mismatched: [String] = []
        var missing: [String] = []
        for entry in manifest.entries {
            switch blobs.verify(entry.digest) {
            case .intact: break
            case .missing: missing.append(entry.digest)
            case .altered: mismatched.append(entry.digest)
            }
        }

        let state: ManifestVerification.State =
            (mismatched.isEmpty && missing.isEmpty) ? .valid : .artifactsChanged
        return ManifestVerification(state: state, mismatched: mismatched, missing: missing)
    }

    public struct ManifestVerification: Sendable, Equatable {
        public enum State: String, Sendable {
            case valid
            case absent
            case unreadable
            /// The manifest itself was altered after signing.
            case signatureInvalid
            /// The signature holds, but artifacts it declares no longer match.
            case artifactsChanged
        }

        public let state: State
        public let mismatched: [String]
        public let missing: [String]

        public var isValid: Bool { state == .valid }

        public var summary: String {
            switch state {
            case .valid: "Manifest signature valid; every artifact matches"
            case .absent: "No manifest has been written for this case"
            case .unreadable: "The manifest could not be read"
            case .signatureInvalid: "The manifest was altered after it was signed"
            case .artifactsChanged:
                "Manifest signature valid, but \(mismatched.count) artifact(s) altered "
                + "and \(missing.count) missing"
            }
        }
    }

    // MARK: Integrity

    /// Re-hashes every artifact this case references and reports what does not match.
    public func verify() throws -> IntegrityReport {
        let referenced: [String] = try queue.read { db in
            try String.fetchAll(db, sql: """
                SELECT DISTINCT digest FROM artifact
                UNION
                SELECT DISTINCT textDigest FROM visit WHERE textDigest IS NOT NULL
                """)
        }

        var missing: [String] = []
        var altered: [String] = []

        for digest in referenced {
            switch blobs.verify(digest) {
            case .intact: break
            case .missing: missing.append(digest)
            case .altered: altered.append(digest)
            }
        }

        let stored = Set((try? blobs.allDigests()) ?? [])
        let unreferenced = stored.subtracting(referenced).sorted()

        let report = IntegrityReport(
            checked: referenced.count,
            missing: missing,
            altered: altered,
            unreferenced: unreferenced
        )

        try queue.write { db in
            var event = CustodyEvent(
                kind: report.isClean ? .verificationRun : .verificationFailed,
                detail: report.summary
            )
            try event.insert(db)
        }

        return report
    }

    public struct IntegrityReport: Sendable, Equatable {
        public let checked: Int
        /// Referenced by a visit but absent from the blob store.
        public let missing: [String]
        /// Present, but its contents no longer hash to the name it is filed under.
        public let altered: [String]
        /// Present but referenced by nothing. Not a failure — an interrupted write can leave
        /// one — but worth reporting.
        public let unreferenced: [String]

        public var isClean: Bool { missing.isEmpty && altered.isEmpty }

        public var summary: String {
            let subject = checked == 1 ? "1 artifact" : "\(checked) artifacts"
            if isClean {
                return "Verified \(subject), all intact"
            }
            var parts: [String] = []
            if !altered.isEmpty { parts.append("\(altered.count) altered") }
            if !missing.isEmpty { parts.append("\(missing.count) missing") }
            return "Verified \(subject) — " + parts.joined(separator: ", ")
        }
    }
}
