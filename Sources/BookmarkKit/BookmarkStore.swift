// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import ShinobiKit

/// The bookmark collection.
public final class BookmarkStore: @unchecked Sendable {

    private let fileURL: URL
    private let queue = DispatchQueue(label: "com.shinobi.browser.bookmark-store")
    private var bookmarks: [Bookmark]

    public var onChange: (@Sendable ([Bookmark]) -> Void)?

    /// - Parameter seedIfEmpty: fills a fresh install with the starter set. A first run with an
    ///   empty bookmark menu teaches the user there is nothing there, and they stop looking.
    public init(fileURL: URL? = nil, seedIfEmpty: Bool = true) {
        self.fileURL = fileURL ?? Self.defaultFileURL()
        self.bookmarks = Self.load(from: self.fileURL)

        if bookmarks.isEmpty, seedIfEmpty, !FileManager.default.fileExists(atPath: self.fileURL.path) {
            // Only on a genuinely fresh install. Someone who has deleted every bookmark meant
            // to, and having them reappear would be its own kind of bug.
            bookmarks = StarterBookmarks.all()
            try? persist()
        }
    }

    public static func defaultFileURL() -> URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Shinobi", isDirectory: true)
        try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        return support.appendingPathComponent("bookmarks.json")
    }

    public var all: [Bookmark] { queue.sync { bookmarks } }

    public func bookmark(withID id: UUID) -> Bookmark? {
        queue.sync { bookmarks.first { $0.id == id } }
    }

    /// Folders in a stable order: the starter folders first, in their intended order, then any
    /// the investigator has added, alphabetically.
    public func folders() -> [String] {
        let present = Set(all.map(\.folder))
        let known = StarterBookmarks.folderOrder.filter(present.contains)
        let added = present.subtracting(known).sorted()
        return known + added
    }

    public func bookmarks(inFolder folder: String) -> [Bookmark] {
        all.filter { $0.folder == folder }.sorted { $0.title < $1.title }
    }

    // MARK: Editing

    public func add(_ bookmark: Bookmark) throws { try mutate { $0.append(bookmark) } }

    public func update(_ bookmark: Bookmark) throws {
        try mutate { list in
            guard let index = list.firstIndex(where: { $0.id == bookmark.id }) else { return }
            list[index] = bookmark
        }
    }

    public func remove(id: UUID) throws { try mutate { $0.removeAll { $0.id == id } } }

    /// Records that a bookmark was opened, which is what moves it up the match list.
    public func recordUse(id: UUID) {
        try? mutate { list in
            guard let index = list.firstIndex(where: { $0.id == id }) else { return }
            list[index].useCount += 1
            list[index].lastUsedAt = Date()
        }
    }

    /// Whether this address is already bookmarked, for the add/remove toggle.
    public func existing(for url: String) -> Bookmark? {
        let normalised = Self.normalise(url)
        return all.first { Self.normalise($0.url) == normalised }
    }

    static func normalise(_ url: String) -> String {
        var value = url.lowercased()
        for prefix in ["https://", "http://"] where value.hasPrefix(prefix) {
            value = String(value.dropFirst(prefix.count))
        }
        if value.hasPrefix("www.") { value = String(value.dropFirst(4)) }
        while value.hasSuffix("/") { value = String(value.dropLast()) }
        return value
    }

    private func mutate(_ body: (inout [Bookmark]) -> Void) throws {
        try queue.sync {
            body(&bookmarks)
            try persist()
        }
        let snapshot = all
        let handler = onChange
        DispatchQueue.main.async { handler?(snapshot) }
    }

    private func persist() throws {
        let data = try JSONEncoder.shinobi(prettyPrinted: true).encode(bookmarks)
        try data.write(to: fileURL, options: .atomic)
    }

    private static func load(from url: URL) -> [Bookmark] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder.shinobi().decode([Bookmark].self, from: data)) ?? []
    }
}
