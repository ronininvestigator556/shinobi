// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

/// A saved address.
public struct Bookmark: Codable, Identifiable, Sendable, Equatable, Hashable {

    public let id: UUID
    public var title: String
    public var url: String
    /// The folder it sits in. A flat name rather than a tree: investigators sort by the kind
    /// of record a site holds, and one level of grouping covers that without turning
    /// bookmarking into filing.
    public var folder: String
    /// Optional short word to type in the address bar to reach it.
    public var keyword: String?
    /// What it is good for, when that is not obvious from the name.
    public var note: String?
    /// True when the site needs an account or payment to be useful. Shown, because finding
    /// out at the paywall wastes the trip.
    public var requiresAccount: Bool

    public var createdAt: Date
    public var lastUsedAt: Date?
    /// How often it has been opened from Shinobi, used to order matches.
    public var useCount: Int

    public init(
        id: UUID = UUID(),
        title: String,
        url: String,
        folder: String,
        keyword: String? = nil,
        note: String? = nil,
        requiresAccount: Bool = false,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.url = url
        self.folder = folder
        self.keyword = keyword
        self.note = note
        self.requiresAccount = requiresAccount
        self.createdAt = createdAt
        self.useCount = 0
    }

    public var host: String { URL(string: url)?.host ?? url }

    /// Whether the address carries a `{query}` placeholder, making it a search rather than a
    /// destination.
    public var isSearch: Bool { url.contains("{query}") }

    /// The address to open, with a query substituted if this is a search bookmark.
    public func resolvedURL(query: String? = nil) -> URL? {
        guard isSearch else { return URL(string: url) }
        guard let query, !query.isEmpty else {
            // Without a term, fall back to the site itself rather than sending a literal
            // "{query}" to someone's search endpoint.
            guard let components = URLComponents(string: url),
                  let host = components.host,
                  let scheme = components.scheme else { return nil }
            return URL(string: "\(scheme)://\(host)")
        }
        let encoded = query.addingPercentEncoding(
            withAllowedCharacters: .alphanumerics.union(.init(charactersIn: "-._~"))) ?? query
        return URL(string: url.replacingOccurrences(of: "{query}", with: encoded))
    }
}
