// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import Testing

@testable import BookmarkKit

@Suite("Bookmark matching")
struct BookmarkMatcherTests {

    private let library: [Bookmark] = [
        Bookmark(title: "Companies House (UK)",
                 url: "https://find-and-update.company-information.service.gov.uk/search?q={query}",
                 folder: "Business"),
        Bookmark(title: "OpenCorporates", url: "https://opencorporates.com/companies?q={query}",
                 folder: "Business"),
        Bookmark(title: "DuckDuckGo", url: "https://duckduckgo.com/?q={query}",
                 folder: "Search", keyword: "ddg"),
        Bookmark(title: "Google Maps", url: "https://www.google.com/maps", folder: "Maps & Geolocation"),
        Bookmark(title: "SunCalc", url: "https://www.suncalc.org/", folder: "Maps & Geolocation",
                 note: "Sun position by date and place, for dating a photograph from shadows"),
    ]

    private func titles(_ input: String) -> [String] {
        BookmarkMatcher.matches(for: input, in: library).map(\.bookmark.title)
    }

    @Test("A keyword goes straight to its bookmark")
    func keywordWins() {
        #expect(titles("ddg").first == "DuckDuckGo")
    }

    @Test("Typing a host finds it")
    func hostPrefixMatches() {
        #expect(titles("opencorp").first == "OpenCorporates")
    }

    @Test("Typing a word from the title finds it")
    func titleWordMatches() {
        // "companies" is the second word of "Companies House", and the whole point is that an
        // investigator types what they remember rather than what the entry starts with.
        #expect(titles("companies").contains("Companies House (UK)"))
    }

    @Test("A folder name surfaces its contents")
    func folderMatches() {
        let found = titles("maps")
        #expect(found.contains("Google Maps"))
        #expect(found.contains("SunCalc"))
        // But the specific match still comes first.
        #expect(found.first == "Google Maps")
    }

    @Test("What a site is for is searchable, not just its name")
    func noteMatches() {
        // Rescues the common case: you remember the job, not the brand name.
        #expect(titles("shadows").contains("SunCalc"))
    }

    @Test("One character matches nothing")
    func singleCharacterIsIgnored() {
        // At one character almost everything matches, which is noise rather than help.
        #expect(BookmarkMatcher.matches(for: "c", in: library).isEmpty)
    }

    @Test("Frequently opened bookmarks rank above equals")
    func useCountBreaksTies() {
        var rare = Bookmark(title: "Records A", url: "https://a.example/", folder: "Courts")
        var common = Bookmark(title: "Records B", url: "https://b.example/", folder: "Courts")
        common.useCount = 40
        rare.useCount = 0

        let ordered = BookmarkMatcher.matches(for: "records", in: [rare, common])
        #expect(ordered.first?.bookmark.title == "Records B")
    }

    @Test("Results are bounded")
    func resultsAreBounded() {
        let many = (0..<100).map {
            Bookmark(title: "Record \($0)", url: "https://r\($0).example/", folder: "Courts")
        }
        #expect(BookmarkMatcher.matches(for: "record", in: many, limit: 8).count == 8)
    }
}

@Suite("Search bookmarks")
struct SearchBookmarkTests {

    private let search = Bookmark(title: "DuckDuckGo", url: "https://duckduckgo.com/?q={query}",
                                  folder: "Search")

    @Test("A query is substituted and encoded")
    func querySubstitutes() throws {
        let url = try #require(search.resolvedURL(query: "jane ashcroft & co"))
        #expect(url.absoluteString.contains("jane%20ashcroft") || url.absoluteString.contains("jane%20"))
        // An unencoded ampersand would silently truncate the search term.
        #expect(!url.absoluteString.contains("& co"))
    }

    @Test("A search bookmark with no query opens the site, not a literal placeholder")
    func emptyQueryFallsBack() throws {
        let url = try #require(search.resolvedURL(query: nil))
        #expect(!url.absoluteString.contains("{query}"))
        #expect(url.host == "duckduckgo.com")
    }

    @Test("A plain bookmark is unaffected")
    func plainBookmarksAreUntouched() throws {
        let plain = Bookmark(title: "Maps", url: "https://www.google.com/maps", folder: "Maps")
        #expect(!plain.isSearch)
        #expect(try #require(plain.resolvedURL()).absoluteString == "https://www.google.com/maps")
    }
}

@Suite("Bookmark store")
struct BookmarkStoreTests {

    private func makeStore(seed: Bool = false) -> (BookmarkStore, URL) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("shinobi-bookmarks-\(UUID().uuidString).json")
        return (BookmarkStore(fileURL: url, seedIfEmpty: seed), url)
    }

    @Test("A fresh install is seeded")
    func freshInstallIsSeeded() {
        let (store, url) = makeStore(seed: true)
        defer { try? FileManager.default.removeItem(at: url) }
        // An empty bookmark menu on first run teaches the user there is nothing there.
        #expect(store.all.count > 50)
        #expect(store.folders().contains("Archives"))
    }

    @Test("Deleting everything does not resurrect the starter set")
    func emptiedStoreStaysEmpty() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("shinobi-bookmarks-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }

        let store = BookmarkStore(fileURL: url, seedIfEmpty: true)
        for bookmark in store.all { try store.remove(id: bookmark.id) }
        #expect(store.all.isEmpty)

        // Someone who cleared their bookmarks meant to.
        let reopened = BookmarkStore(fileURL: url, seedIfEmpty: true)
        #expect(reopened.all.isEmpty)
    }

    @Test("Bookmarks survive a reload")
    func bookmarksPersist() throws {
        let (store, url) = makeStore()
        defer { try? FileManager.default.removeItem(at: url) }

        try store.add(Bookmark(title: "Case portal", url: "https://portal.example/",
                               folder: "Courts & Records"))
        let reopened = BookmarkStore(fileURL: url, seedIfEmpty: false)
        #expect(reopened.all.first?.title == "Case portal")
    }

    @Test("An address is recognised however it was typed")
    func duplicateDetectionIgnoresCosmetics() throws {
        let (store, url) = makeStore()
        defer { try? FileManager.default.removeItem(at: url) }
        try store.add(Bookmark(title: "Example", url: "https://www.example.com/",
                               folder: "Reference"))

        // The same page reached by a slightly different address should not bookmark twice.
        #expect(store.existing(for: "https://example.com") != nil)
        #expect(store.existing(for: "http://www.example.com/") != nil)
        #expect(store.existing(for: "https://example.com/other") == nil)
    }

    @Test("Folders come back in a sensible order")
    func foldersAreOrdered() throws {
        let (store, url) = makeStore()
        defer { try? FileManager.default.removeItem(at: url) }
        try store.add(Bookmark(title: "A", url: "https://a.example/", folder: "Archives"))
        try store.add(Bookmark(title: "B", url: "https://b.example/", folder: "Search"))
        try store.add(Bookmark(title: "C", url: "https://c.example/", folder: "My own folder"))

        let folders = store.folders()
        // Known folders keep their intended order; anything added goes after.
        #expect(folders.firstIndex(of: "Search")! < folders.firstIndex(of: "Archives")!)
        #expect(folders.last == "My own folder")
    }
}

@Suite("Starter set")
struct StarterBookmarksTests {

    @Test("Every starter address is a usable URL")
    func addressesAreValid() throws {
        for bookmark in StarterBookmarks.all() {
            let resolved = bookmark.resolvedURL(query: "test")
            #expect(resolved != nil, "\(bookmark.title) produced no URL")
            #expect(resolved?.scheme?.hasPrefix("http") == true, "\(bookmark.title) is not http(s)")
        }
    }

    @Test("No placeholder survives into a resolved address")
    func noPlaceholdersLeak() throws {
        for bookmark in StarterBookmarks.all() {
            let url = try #require(bookmark.resolvedURL(query: "jane"))
            #expect(!url.absoluteString.contains("{query}"), "\(bookmark.title) kept its placeholder")
        }
    }

    @Test("Every starter bookmark sits in a declared folder")
    func foldersAreDeclared() {
        let declared = Set(StarterBookmarks.folderOrder)
        let used = Set(StarterBookmarks.all().map(\.folder))
        #expect(used.subtracting(declared).isEmpty,
                "undeclared folders: \(used.subtracting(declared))")
    }

    @Test("There are no duplicate addresses")
    func noDuplicates() {
        let urls = StarterBookmarks.all().map { BookmarkStore.normalise($0.url) }
        #expect(urls.count == Set(urls).count)
    }

    @Test("Sites needing an account say so")
    func paidSitesAreFlagged() {
        // Finding out at the paywall wastes the trip.
        let all = StarterBookmarks.all()
        let pacer = all.first { $0.title.contains("PACER") }
        #expect(pacer?.requiresAccount == true)
        #expect(all.contains { $0.requiresAccount })
    }
}
