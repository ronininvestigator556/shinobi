// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import GRDB

/// One distinct thing harvested into a case's dossier — an email, a domain, a person's name —
/// with how often it has been seen across the pages recorded in the case. A name seen on one
/// page may be incidental; one seen on twenty is a thread.
public struct DossierEntity: Codable, FetchableRecord, MutablePersistableRecord, Equatable, Sendable {
    public static let databaseTableName = "dossierEntity"

    public var id: Int64?
    /// Category — PivotKit's `Entity.Kind`/`Mention.Kind` raw value ("email", "person", …).
    public var kind: String
    /// As it appeared on the page.
    public var value: String
    /// The deduplication form (lowercased host, stripped separators).
    public var normalised: String
    public var firstSeenAt: Double
    public var lastSeenAt: Double
    /// How many recorded pages it has appeared on.
    public var occurrences: Int

    public var first: Date { Date(timeIntervalSince1970: firstSeenAt) }
    public var last: Date { Date(timeIntervalSince1970: lastSeenAt) }

    public init(kind: String, value: String, normalised: String,
                firstSeenAt: Date, lastSeenAt: Date, occurrences: Int) {
        self.kind = kind
        self.value = value
        self.normalised = normalised
        self.firstSeenAt = firstSeenAt.timeIntervalSince1970
        self.lastSeenAt = lastSeenAt.timeIntervalSince1970
        self.occurrences = occurrences
    }
}

/// A single entity to fold into the dossier. Deliberately free of PivotKit types so CaseKit
/// stays independent of the extraction layer — the app maps PivotKit's results into these.
public struct HarvestedEntity: Sendable, Equatable {
    public let kind: String
    public let value: String
    public let normalised: String
    public init(kind: String, value: String, normalised: String) {
        self.kind = kind
        self.value = value
        self.normalised = normalised
    }
}
