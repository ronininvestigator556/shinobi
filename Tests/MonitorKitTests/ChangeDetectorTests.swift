// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import Testing

@testable import MonitorKit

/// The hard part of monitoring is not fetching a page again — it is that almost every page
/// differs from itself on every load. A watch that reports all of that gets switched off
/// within a day, and then it is not watching anything.
@Suite("Change detection")
struct ChangeDetectorTests {

    private let page = """
    Ashcroft Holdings Limited
    Registered office: 14 Bridge Street, Birmingham
    Status: Active
    Directors: Jane Ashcroft
    Last accounts filed: 2025
    """

    @Test("An identical page is not a change")
    func identicalIsUnchanged() {
        let result = ChangeDetector.compare(previous: page, current: page)
        #expect(!result.changed)
        #expect(result.similarity == 1)
    }

    @Test("Reformatting is not a change")
    func whitespaceIsNotAChange() {
        // Re-rendering the same content with different wrapping happens constantly and means
        // nothing.
        let reflowed = page
            .replacingOccurrences(of: "Registered office:", with: "Registered   office:")
            .replacingOccurrences(of: "\n", with: "\n\n")
        #expect(!ChangeDetector.compare(previous: page, current: reflowed).changed)
    }

    @Test("Reordered sections are not a change")
    func reorderingIsNotAChange() {
        // A page whose blocks are shuffled has not changed in any way an investigator cares
        // about, and a positional diff would call every load a change.
        let shuffled = page.split(separator: "\n").reversed().joined(separator: "\n")
        #expect(!ChangeDetector.compare(previous: page, current: shuffled).changed)
    }

    @Test("A substantive edit is a change, and says what changed")
    func substantiveEditIsReported() {
        let updated = page
            .replacingOccurrences(of: "Status: Active", with: "Status: Dissolved")
            .replacingOccurrences(of: "Directors: Jane Ashcroft",
                                  with: "Directors: Jane Ashcroft, Peter Vance")
        let result = ChangeDetector.compare(previous: page, current: updated,
                                            sensitivity: .any)

        #expect(result.changed)
        #expect(result.addedLines.contains { $0.contains("Dissolved") })
        #expect(result.removedLines.contains { $0.contains("Active") })
        #expect(result.summary.contains("added"))
    }

    // MARK: Sensitivity

    @Test("Minor churn is ignored at the default sensitivity")
    func churnIsIgnoredByDefault() {
        // The lines that differ on almost every load: a view counter, a relative timestamp.
        let long = (0..<200).map { "Content line \($0)" }.joined(separator: "\n")
        let before = long + "\nViews: 1,204\nPosted 3 hours ago"
        let after = long + "\nViews: 1,207\nPosted 4 hours ago"

        #expect(!ChangeDetector.compare(previous: before, current: after).changed)
        // But an investigator who wants to see exactly that can ask for it.
        #expect(ChangeDetector.compare(previous: before, current: after, sensitivity: .any).changed)
    }

    @Test("A real edit is still caught at the default sensitivity")
    func realEditsSurviveTheFloor() {
        // The floor must not be so high that the thing being watched for slips under it.
        let long = (0..<200).map { "Content line \($0)" }.joined(separator: "\n")
        let before = long + "\nStatus: Active\nViews: 1,204"
        let after = long + "\nStatus: Dissolved\nDirectors removed\nNew filing 2026\nViews: 1,207"

        let result = ChangeDetector.compare(previous: before, current: after)
        #expect(result.changed)
        #expect(result.addedLines.contains { $0.contains("Dissolved") })
    }

    @Test("Substantial only fires on a large rewrite")
    func substantialIgnoresSmallEdits() {
        let long = (0..<300).map { "Line \($0)" }.joined(separator: "\n")
        let smallEdit = long.replacingOccurrences(of: "Line 5\n", with: "Line five\n")
        #expect(!ChangeDetector.compare(previous: long, current: smallEdit,
                                        sensitivity: .substantial).changed)

        let rewritten = (0..<300).map { "Different line \($0)" }.joined(separator: "\n")
        #expect(ChangeDetector.compare(previous: long, current: rewritten,
                                       sensitivity: .substantial).changed)
    }

    @Test("Numbers are never stripped")
    func numbersAreNotDiscarded() {
        // A follower count is noise on one page and the finding on another, and the tool is
        // not in a position to know which — so nothing is filtered out by content, only by
        // how much of the page moved.
        let before = "Followers: 1200\nBio: nothing"
        let after = "Followers: 41000\nBio: nothing"
        #expect(ChangeDetector.compare(previous: before, current: after, sensitivity: .any).changed)
    }

    // MARK: Edges

    @Test("A page that appears from nothing is a change")
    func emptyToContentIsAChange() {
        let result = ChangeDetector.compare(previous: "", current: page, sensitivity: .any)
        #expect(result.changed)
    }

    @Test("A page that empties out is a change")
    func contentToEmptyIsAChange() {
        // A profile that has been deleted is exactly what a watch exists to catch.
        let result = ChangeDetector.compare(previous: page, current: "", sensitivity: .any)
        #expect(result.changed)
        #expect(result.removedLines.count >= 4)
    }

    @Test("Reported lines are bounded")
    func reportedLinesAreBounded() {
        let before = (0..<5000).map { "old \($0)" }.joined(separator: "\n")
        let after = (0..<5000).map { "new \($0)" }.joined(separator: "\n")
        let result = ChangeDetector.compare(previous: before, current: after)
        // A wholesale rewrite must not put ten thousand lines into a notification.
        #expect(result.addedLines.count <= 80)
        #expect(result.removedLines.count <= 80)
        #expect(result.changed)
    }
}

@Suite("Watch scheduling")
struct WatchTests {

    private func makeWatch(interval: Watch.Interval = .hourly) -> Watch {
        Watch(name: "Company record", url: "https://example.com/co",
              containerID: UUID(), interval: interval)
    }

    @Test("A watch that has never run is due")
    func neverCheckedIsDue() {
        #expect(makeWatch().isDue())
    }

    @Test("A watch checked recently is not due")
    func recentlyCheckedIsNotDue() {
        var watch = makeWatch()
        watch.lastCheckedAt = Date()
        #expect(!watch.isDue())
    }

    @Test("A watch becomes due once its interval has passed")
    func intervalElapsesIntoDue() {
        var watch = makeWatch(interval: .fifteenMinutes)
        watch.lastCheckedAt = Date().addingTimeInterval(-16 * 60)
        #expect(watch.isDue())
    }

    @Test("A paused watch is never due")
    func pausedIsNeverDue() {
        var watch = makeWatch()
        watch.isEnabled = false
        watch.lastCheckedAt = Date().addingTimeInterval(-10_000)
        #expect(!watch.isDue())
    }

    @Test("Jitter stays within a fifth of the interval")
    func jitterIsBounded() {
        // Polling a subject's page at exactly the same second past the hour, forever, is a
        // legible pattern in their access logs. Jitter does not hide monitoring, but it stops
        // the schedule itself being the tell.
        for _ in 0..<200 {
            let jitter = Watch.jitter(for: .hourly)
            #expect(jitter >= 0)
            #expect(jitter <= Watch.Interval.hourly.seconds * 0.2)
        }
        #expect(Set((0..<20).map { _ in Watch.jitter(for: .hourly) }).count > 1)
    }

    @Test("A failing watch says so rather than reporting no change")
    func failuresAreVisible() {
        // "Could not reach the page" and "the page has not changed" are different facts, and
        // conflating them means an investigator believes they are covered when they are not.
        var watch = makeWatch()
        watch.consecutiveFailures = 3
        watch.lastError = "The server did not respond."
        #expect(watch.statusLine.contains("failed"))
        #expect(!watch.statusLine.contains("No change"))
    }
}

@Suite("Watch store")
struct WatchStoreTests {

    private func makeStore() -> (WatchStore, URL) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("shinobi-watches-\(UUID().uuidString).json")
        return (WatchStore(fileURL: url), url)
    }

    @Test("Watches survive a reload")
    func watchesPersist() throws {
        let (store, url) = makeStore()
        defer { try? FileManager.default.removeItem(at: url) }

        let watch = Watch(name: "Filing history", url: "https://example.com/x",
                          containerID: UUID(), interval: .daily)
        try store.add(watch)

        let reloaded = WatchStore(fileURL: url)
        #expect(reloaded.all.count == 1)
        #expect(reloaded.watch(withID: watch.id)?.name == "Filing history")
        #expect(reloaded.watch(withID: watch.id)?.interval == .daily)
    }

    @Test("Only due watches come back from due()")
    func dueFiltersCorrectly() throws {
        let (store, url) = makeStore()
        defer { try? FileManager.default.removeItem(at: url) }

        var recent = Watch(name: "Recent", url: "https://a.test", containerID: UUID())
        recent.lastCheckedAt = Date()
        var stale = Watch(name: "Stale", url: "https://b.test", containerID: UUID())
        stale.lastCheckedAt = Date().addingTimeInterval(-7200)

        try store.add(recent)
        try store.add(stale)

        let due = store.due()
        #expect(due.count == 1)
        #expect(due.first?.name == "Stale")
    }

    @Test("Updating a watch rewrites it in place")
    func updateWorks() throws {
        let (store, url) = makeStore()
        defer { try? FileManager.default.removeItem(at: url) }

        var watch = Watch(name: "Before", url: "https://a.test", containerID: UUID())
        try store.add(watch)
        watch.name = "After"
        watch.lastDigest = "abc"
        try store.update(watch)

        let reloaded = WatchStore(fileURL: url)
        #expect(reloaded.all.count == 1)
        #expect(reloaded.watch(withID: watch.id)?.name == "After")
        #expect(reloaded.watch(withID: watch.id)?.lastDigest == "abc")
    }

    @Test("A corrupt file leaves an empty list rather than crashing")
    func corruptFileRecovers() throws {
        let (_, url) = makeStore()
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("{ not json".utf8).write(to: url)
        #expect(WatchStore(fileURL: url).all.isEmpty)
    }
}

@Suite("Sensitivity scaling")
struct SensitivityScalingTests {

    @Test("On a short record, a single changed line is a change")
    func shortPagesAreExact() {
        // A fixed allowance is wrong in both directions. Two changed lines on a six-line
        // company record is the record moving; the same two lines in a long forum thread is a
        // view counter. Short pages get no allowance.
        let before = """
        Ashcroft Holdings Limited
        Status: Active
        Directors: Jane Ashcroft
        Accounts: 2025
        """
        let after = before.replacingOccurrences(of: "Status: Active", with: "Status: Dissolved")

        #expect(ChangeDetector.compare(previous: before, current: after).changed)
    }

    @Test("On a long page, the same amount of churn is ignored")
    func longPagesTolerateChurn() {
        let body = (0..<400).map { "Comment number \($0)" }.joined(separator: "\n")
        let before = body + "\nViews: 1,204\nPosted 3 hours ago"
        let after = body + "\nViews: 1,207\nPosted 4 hours ago"

        #expect(!ChangeDetector.compare(previous: before, current: after).changed)
    }

    @Test("The allowance never hides a change bigger than itself")
    func allowanceDoesNotSwallowRealEdits() {
        let body = (0..<400).map { "Comment number \($0)" }.joined(separator: "\n")
        let before = body + "\nStatus: Active\nViews: 1,204"
        let after = body + "\nStatus: Dissolved\nAccount suspended\nAppeal pending\nViews: 1,207"

        let result = ChangeDetector.compare(previous: before, current: after)
        #expect(result.changed)
        #expect(result.addedLines.contains { $0.contains("suspended") })
    }
}
