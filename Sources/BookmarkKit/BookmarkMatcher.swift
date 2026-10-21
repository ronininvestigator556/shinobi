// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

/// Matches what has been typed in the address bar against the bookmarks.
///
/// Ranked rather than merely filtered. An investigator who types three characters wants the
/// site they open every day, not the alphabetically first of forty matches — so a prefix match
/// on the title beats a match buried in the middle of a URL, an exact keyword beats everything,
/// and among equals the one opened most often wins.
public enum BookmarkMatcher {

    public struct Match: Sendable, Equatable {
        public let bookmark: Bookmark
        public let score: Int
        /// What the address bar should be completed to.
        public var completion: String { bookmark.url }
    }

    public static func matches(for input: String, in bookmarks: [Bookmark], limit: Int = 8) -> [Match] {
        let query = input.trimmingCharacters(in: .whitespaces).lowercased()
        // One character matches almost everything and is more noise than help.
        guard query.count >= 2 else { return [] }

        var results: [Match] = []
        for bookmark in bookmarks {
            guard let score = score(bookmark, against: query) else { continue }
            results.append(Match(bookmark: bookmark, score: score))
        }

        return results
            .sorted {
                if $0.score != $1.score { return $0.score > $1.score }
                if $0.bookmark.useCount != $1.bookmark.useCount {
                    return $0.bookmark.useCount > $1.bookmark.useCount
                }
                return $0.bookmark.title < $1.bookmark.title
            }
            .prefix(limit)
            .map { $0 }
    }

    /// Higher is a better match. Nil means no match at all.
    private static func score(_ bookmark: Bookmark, against query: String) -> Int? {
        let title = bookmark.title.lowercased()
        let host = bookmark.host.lowercased()
        let folder = bookmark.folder.lowercased()

        // A keyword is an explicit instruction, so it outranks anything inferred.
        if let keyword = bookmark.keyword?.lowercased() {
            if keyword == query { return 1000 }
            if keyword.hasPrefix(query) { return 700 }
        }

        if host == query { return 900 }
        if title == query { return 850 }

        // A host the investigator has started typing is almost always what they mean.
        if host.hasPrefix(query) { return 600 }
        if title.hasPrefix(query) { return 550 }

        // A word inside the title: "companies" should find "Companies House".
        if title.split(separator: " ").contains(where: { $0.hasPrefix(query) }) { return 450 }

        if host.contains(query) { return 300 }
        if title.contains(query) { return 250 }

        // Folder last: typing "maps" surfacing everything geographic is useful, but only once
        // the more specific matches have had their turn.
        if folder.contains(query) { return 120 }

        // A note match is the weakest signal but rescues the case where someone remembers what
        // a site was for and not what it was called.
        if bookmark.note?.lowercased().contains(query) == true { return 80 }

        return nil
    }
}
