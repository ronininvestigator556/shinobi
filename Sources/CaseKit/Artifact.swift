// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import GRDB

/// One preserved thing belonging to a visit.
///
/// A visit produces several: the readable text that feeds the index, a self-contained HTML
/// archive, a full-page screenshot, a PDF. Each is stored under the SHA-256 of its own bytes
/// and recorded here, so "what exactly is being offered as this exhibit" has a precise answer
/// rather than a gesture at a folder.
public struct Artifact: Codable, FetchableRecord, MutablePersistableRecord, Equatable, Sendable {
    public static let databaseTableName = "artifact"

    public enum Kind: String, Codable, Sendable, CaseIterable {
        /// Readable text, as rendered. Feeds the search index.
        case text
        /// Self-contained HTML, scripts removed. The fullest record of the page.
        case archive
        /// Full-page PNG.
        case screenshot
        /// Paginated PDF.
        case pdf
        /// Machine transcription of a screenshot. Kept distinct from `.text` because it is a
        /// reading of pixels, not the page's own words, and a report must be able to tell the
        /// two apart.
        case ocr

        public var displayName: String {
            switch self {
            case .text: "Page text"
            case .archive: "HTML archive"
            case .screenshot: "Screenshot"
            case .pdf: "PDF"
            case .ocr: "Transcribed text"
            }
        }

        public var fileExtension: String {
            switch self {
            case .text: "txt"
            case .archive: "html"
            case .screenshot: "png"
            case .pdf: "pdf"
            case .ocr: "txt"
            }
        }
    }

    public var id: Int64?
    public var visitID: Int64
    public var kind: String
    public var digest: String
    public var byteCount: Int
    public var createdAt: Double
    /// Fidelity caveats belonging with this artifact — resources that could not be inlined,
    /// a screenshot cut short, scripts removed. Carried into any export.
    public var note: String?

    public init(
        visitID: Int64,
        kind: Kind,
        digest: String,
        byteCount: Int,
        note: String? = nil,
        createdAt: Date = Date()
    ) {
        self.visitID = visitID
        self.kind = kind.rawValue
        self.digest = digest
        self.byteCount = byteCount
        self.note = note
        self.createdAt = createdAt.timeIntervalSince1970
    }

    public var artifactKind: Kind? { Kind(rawValue: kind) }
    public var created: Date { Date(timeIntervalSince1970: createdAt) }

    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}
