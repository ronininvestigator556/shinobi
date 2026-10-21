// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import Testing

@testable import BookmarkKit
import ShinobiKit

/// The state-resources set ships by default, so a broken entry is a dead link in front of
/// every investigator on first launch. These pin the structure, not the specific agencies.
@Suite("State resources")
struct StateResourcesTests {

    @Test("All 50 states are present, each its own folder")
    func allFiftyStates() {
        #expect(StateResources.folderNames.count == 50)
        #expect(Set(StateResources.folderNames).count == 50)   // no duplicates
        #expect(StateResources.folderNames.contains("Alabama"))
        #expect(StateResources.folderNames.contains("Wyoming"))
    }

    @Test("Every entry has an https URL and lands in its state folder")
    func everyEntryWellFormed() {
        let folders = Set(StateResources.folderNames)
        for bookmark in StateResources.all() {
            #expect(bookmark.url.hasPrefix("https://") || bookmark.url.hasPrefix("http://"),
                    "\(bookmark.folder) / \(bookmark.title): \(bookmark.url)")
            #expect(folders.contains(bookmark.folder))
            #expect(!bookmark.title.isEmpty)
            #expect(URL(string: bookmark.url) != nil, "unparseable: \(bookmark.url)")
        }
    }

    @Test("No research placeholder text leaked into the shipped data")
    func noPlaceholders() {
        for bookmark in StateResources.all() {
            let haystack = "\(bookmark.title) \(bookmark.url) \(bookmark.note ?? "")"
            #expect(!haystack.contains("UNVERIFIED"))
            #expect(!haystack.lowercased().contains("best guess"))
            #expect(!bookmark.url.contains(" "))
        }
    }

    @Test("Alabama — the home state — has its core searches")
    func alabamaCoreSearches() {
        let alabama = StateResources.all().filter { $0.folder == "Alabama" }
        let titles = Set(alabama.map(\.title))
        #expect(titles.contains("Business Search"))
        #expect(titles.contains("Court Records"))
        #expect(titles.contains("Inmate Search"))
        #expect(titles.contains("Sex Offender Registry"))
        #expect(alabama.first { $0.title == "Business Search" }?.url == "https://arc-sos.state.al.us/CGI/CORPNAME.MBR/INPUT")
    }

    @Test("The state folders are appended to the starter menu order")
    func foldersInStarterOrder() {
        #expect(StarterBookmarks.folderOrder.contains("Alabama"))
        #expect(StarterBookmarks.all().contains { $0.folder == "Alabama" })
    }

    @Test("A store predating the feature is topped up once, and deletions stick")
    func topsUpExistingStoreOnce() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("bkm-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("bookmarks.json")

        // An old store: OSINT bookmarks only, no state folders, no marker file.
        let old = [Bookmark(title: "DuckDuckGo", url: "https://duckduckgo.com/?q={query}", folder: "Search")]
        try JSONEncoder.shinobi().encode(old).write(to: file)

        let store = BookmarkStore(fileURL: file)
        #expect(store.folders().contains("Alabama"))
        #expect(!store.bookmarks(inFolder: "Wyoming").isEmpty)

        // Delete a state bookmark; reopening must not resurrect it — the marker gates the top-up.
        let removedID = store.bookmarks(inFolder: "Alabama").first!.id
        try store.remove(id: removedID)
        let reopened = BookmarkStore(fileURL: file)
        #expect(reopened.bookmark(withID: removedID) == nil)
    }
}
