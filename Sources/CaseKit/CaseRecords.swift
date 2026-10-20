// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import GRDB

/// Identifying information for the case a bundle holds. Exactly one row.
public struct CaseInfo: Codable, FetchableRecord, PersistableRecord, Equatable, Sendable {
    public static let databaseTableName = "caseInfo"

    public var id: Int64 = 1
    /// What the investigator calls it.
    public var name: String
    /// The client or court reference, when there is one.
    public var reference: String?
    public var createdAt: Double
    public var openedAt: Double

    public init(name: String, reference: String? = nil, createdAt: Date = Date(), openedAt: Date = Date()) {
        self.name = name
        self.reference = reference
        self.createdAt = createdAt.timeIntervalSince1970
        self.openedAt = openedAt.timeIntervalSince1970
    }

    public var created: Date { Date(timeIntervalSince1970: createdAt) }
    public var opened: Date { Date(timeIntervalSince1970: openedAt) }
}

/// One page the investigator looked at.
///
/// Timestamps are stored as epoch seconds in a REAL column rather than as text. A `Date` does
/// not survive an ISO-8601 round trip at sub-second precision — the text is stable but the
/// `Double` rebuilt from it is not — and a case file needs its times to come back exactly as
/// they went in, both for ordering rapid visits and for hashing later.
public struct Visit: Codable, FetchableRecord, MutablePersistableRecord, Equatable, Sendable {
    public static let databaseTableName = "visit"

    public var id: Int64?
    public var url: String
    public var host: String?
    public var title: String
    /// Which identity was used. Recorded because "who was I browsing as" is a question an
    /// exhibit has to be able to answer.
    public var containerID: String
    public var containerName: String
    public var visitedAt: Double
    /// Digest of the extracted plain text, when it was captured.
    public var textDigest: String?
    public var textLength: Int?
    /// True when the page was served over TLS.
    public var secure: Bool

    public init(
        url: String,
        title: String,
        containerID: String,
        containerName: String,
        secure: Bool,
        visitedAt: Date = Date(),
        textDigest: String? = nil,
        textLength: Int? = nil
    ) {
        self.url = url
        self.host = URL(string: url)?.host
        self.title = title
        self.containerID = containerID
        self.containerName = containerName
        self.secure = secure
        self.visitedAt = visitedAt.timeIntervalSince1970
        self.textDigest = textDigest
        self.textLength = textLength
    }

    public var visited: Date { Date(timeIntervalSince1970: visitedAt) }

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

/// An investigator's note, optionally attached to a visit.
public struct Note: Codable, FetchableRecord, MutablePersistableRecord, Equatable, Sendable {
    public static let databaseTableName = "note"

    public var id: Int64?
    public var body: String
    public var createdAt: Double
    public var visitID: Int64?

    public init(body: String, visitID: Int64? = nil, createdAt: Date = Date()) {
        self.body = body
        self.visitID = visitID
        self.createdAt = createdAt.timeIntervalSince1970
    }

    public var created: Date { Date(timeIntervalSince1970: createdAt) }

    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

/// An entry in the case's append-only chain-of-custody log.
///
/// Never updated and never deleted. The log's value in a challenge comes precisely from its
/// being a record of what happened rather than a summary of the current state, so the store
/// exposes no way to amend one.
public struct CustodyEvent: Codable, FetchableRecord, MutablePersistableRecord, Equatable, Sendable {
    public static let databaseTableName = "custodyEvent"

    public enum Kind: String, Codable, Sendable {
        case caseCreated
        case caseOpened
        case caseClosed
        case visitRecorded
        case noteAdded
        case verificationRun
        case verificationFailed
    }

    public var id: Int64?
    public var kind: String
    public var detail: String
    public var occurredAt: Double

    public init(kind: Kind, detail: String, occurredAt: Date = Date()) {
        self.kind = kind.rawValue
        self.detail = detail
        self.occurredAt = occurredAt.timeIntervalSince1970
    }

    public var occurred: Date { Date(timeIntervalSince1970: occurredAt) }

    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

/// A full-text hit, with the surrounding words.
public struct SearchHit: FetchableRecord, Equatable, Sendable {
    public var visitID: Int64
    public var url: String
    public var title: String
    public var containerName: String
    public var visitedAt: Double
    /// The matching text with the query terms marked, from FTS5's own snippet function.
    public var snippet: String

    public var visited: Date { Date(timeIntervalSince1970: visitedAt) }

    public init(row: Row) {
        visitID = row["visitID"]
        url = row["url"]
        title = row["title"]
        containerName = row["containerName"]
        visitedAt = row["visitedAt"]
        snippet = row["snippet"]
    }
}
