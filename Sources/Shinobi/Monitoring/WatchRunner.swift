// SPDX-License-Identifier: GPL-3.0-or-later
import AppKit
import CaptureKit
import CaseKit
import IdentityKit
import Combine
import MonitorKit
import PivotKit
import UserNotifications
import WebKit

/// Runs the watch list.
///
/// Checks load the page in an offscreen web view built from the watch's own identity, rather
/// than fetching the HTML with `URLSession`. Two reasons, and both matter for this job: a
/// profile or a filing page is usually rendered by script, so a raw fetch would compare two
/// empty shells and report "no change" forever; and loading it through the identity means the
/// check leaves from the same address the investigator browsed from, instead of quietly
/// polling a subject from the machine's own connection every hour.
@MainActor
final class WatchRunner {

    private let store: WatchStore
    private let identities: IdentityStore
    private let sessions: IdentitySessionProvider

    private var timer: Timer?
    private var isChecking = false

    /// Fires when a watch reports a change, so the interface can surface it.
    let didObserveChange = PassthroughSubject<(Watch, ChangeDetector.Comparison), Never>()
    let didChangeList = PassthroughSubject<Void, Never>()

    init(store: WatchStore, identities: IdentityStore, sessions: IdentitySessionProvider) {
        self.store = store
        self.identities = identities
        self.sessions = sessions
    }

    // MARK: Scheduling

    func start() {
        requestNotificationPermission()
        // A one-minute tick decides only *whether* anything is due; the watch's own interval
        // and jitter decide when it actually runs.
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.runDueChecks() }
        }
        runDueChecks()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func runDueChecks() {
        guard !isChecking else { return }
        let due = store.due()
        guard !due.isEmpty else { return }

        isChecking = true
        Task { [weak self] in
            guard let self else { return }
            // Sequentially, not in parallel: several offscreen web views loading at once is
            // both heavy and a burst of simultaneous requests that looks nothing like a person.
            for watch in due {
                await self.check(watch)
            }
            self.isChecking = false
        }
    }

    /// Runs one check now, regardless of schedule.
    func checkNow(_ watch: Watch) {
        Task { await check(watch) }
    }

    // MARK: Checking

    private func check(_ watch: Watch) async {
        var updated = watch
        updated.lastCheckedAt = Date()

        guard let url = URL(string: watch.url),
              let identity = identities.identity(withID: watch.containerID) else {
            updated.consecutiveFailures += 1
            updated.lastError = "The page or its identity is no longer configured."
            try? store.update(updated)
            didChangeList.send()
            return
        }

        do {
            let (text, webView) = try await loadText(url, in: identity)
            defer { webView.removeFromSuperview() }

            updated.consecutiveFailures = 0
            updated.lastError = nil

            let digest = BlobStore.digest(of: Data(text.utf8))
            guard let previousDigest = updated.lastDigest else {
                // First look establishes the baseline. It is not a change, and reporting one
                // would train the investigator to dismiss the first alert from every watch.
                updated.lastDigest = digest
                updated.lastLength = text.count
                try? store.update(updated)
                didChangeList.send()
                return
            }

            guard digest != previousDigest else {
                try? store.update(updated)
                didChangeList.send()
                return
            }

            // The digest only says the bytes differ. Whether that is a *change* is the
            // detector's judgement, and most byte differences are not.
            let previousText = storedText(for: watch) ?? ""
            let comparison = ChangeDetector.compare(
                previous: previousText, current: text, sensitivity: watch.sensitivity)

            updated.lastDigest = digest
            updated.lastLength = text.count
            storeText(text, for: watch)

            if comparison.changed {
                updated.lastChangedAt = Date()
                try? store.update(updated)
                await recordChange(watch, comparison: comparison, webView: webView, url: url)
                notify(watch, comparison)
                didObserveChange.send((updated, comparison))
            } else {
                try? store.update(updated)
            }
            didChangeList.send()
        } catch {
            updated.consecutiveFailures += 1
            updated.lastError = error.localizedDescription
            try? store.update(updated)
            didChangeList.send()

            // A watch that cannot reach its page is not a watch reporting no change. After
            // three failures the investigator is told, because silence would otherwise read
            // as "nothing is happening".
            if updated.consecutiveFailures == 3 {
                notifyFailure(updated)
            }
        }
    }

    /// Loads the page offscreen in its identity and returns the rendered text.
    private func loadText(_ url: URL, in identity: Identity) async throws -> (String, WKWebView) {
        let configuration = try sessions.configuration(for: identity)
        let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 1280, height: 900),
                                configuration: configuration)
        webView.customUserAgent = identity.userAgent.stringValue

        let waiter = LoadWaiter()
        webView.navigationDelegate = waiter

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            waiter.onFinish = { error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume() }
            }
            webView.load(URLRequest(url: url))
        }

        // Give script-rendered content a moment to appear. Without this a modern profile page
        // reads as empty and every check reports no change forever.
        try? await Task.sleep(for: .seconds(3))

        let text = await PageTextExtractor.extract(from: webView) ?? ""
        _ = waiter
        return (text, webView)
    }

    // MARK: Recording

    /// Writes the changed page into the watch's case, if it has one.
    ///
    /// This is the point of tying watches to cases: the change *is* the evidence, and it needs
    /// preserving at the moment it is noticed rather than whenever the investigator next looks.
    private func recordChange(
        _ watch: Watch,
        comparison: ChangeDetector.Comparison,
        webView: WKWebView,
        url: URL
    ) async {
        guard let path = watch.casePath,
              let store = try? CaseStore(bundle: CaseBundle(url: URL(fileURLWithPath: path))),
              let identity = identities.identity(withID: watch.containerID)
        else { return }

        let text = await PageTextExtractor.extract(from: webView)
        guard let recorded = try? store.record(
            url: url.absoluteString,
            title: webView.title ?? watch.name,
            containerID: identity.id.uuidString,
            containerName: identity.name,
            secure: url.scheme == "https",
            text: text
        ) else { return }

        if let archive = try? await PageArchiver.archive(webView) {
            try? store.attach(.archive, data: archive.data, to: recorded.id,
                              note: "Captured automatically when this page changed")
        }
        if let snapshot = try? await PageSnapshotter.screenshot(of: webView) {
            try? store.attach(.screenshot, data: snapshot.png, to: recorded.id,
                              note: "Captured automatically when this page changed")
        }

        // The diff itself is kept, because "what changed" is a separate fact from "what the
        // page says now", and only the first answers why the capture exists.
        var note = "Watch '\(watch.name)' observed a change.\n\(comparison.summary)\n"
        if !comparison.addedLines.isEmpty {
            note += "\nAdded:\n" + comparison.addedLines.prefix(40).map { "+ \($0)" }
                .joined(separator: "\n")
        }
        if !comparison.removedLines.isEmpty {
            note += "\n\nRemoved:\n" + comparison.removedLines.prefix(40).map { "- \($0)" }
                .joined(separator: "\n")
        }
        try? store.attach(.text, data: Data(note.utf8), to: recorded.id,
                          note: "Difference from the previous check")
        try? store.addNote(note, visitID: recorded.id)
    }

    // MARK: Previous text

    /// Previous readings live beside the watch list rather than in a case, because a watch may
    /// have no case and still needs something to compare against.
    private func textURL(for watch: Watch) -> URL {
        let directory = WatchStore.defaultFileURL().deletingLastPathComponent()
            .appendingPathComponent("WatchState", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("\(watch.id.uuidString).txt")
    }

    private func storedText(for watch: Watch) -> String? {
        try? String(contentsOf: textURL(for: watch), encoding: .utf8)
    }

    private func storeText(_ text: String, for watch: Watch) {
        try? text.write(to: textURL(for: watch), atomically: true, encoding: .utf8)
    }

    // MARK: Notifications

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func notify(_ watch: Watch, _ comparison: ChangeDetector.Comparison) {
        let content = UNMutableNotificationContent()
        content.title = "\(watch.name) changed"
        content.body = comparison.summary
        if let first = comparison.addedLines.first {
            content.body += "\n\(first.prefix(120))"
        }
        content.sound = .default
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }

    private func notifyFailure(_ watch: Watch) {
        let content = UNMutableNotificationContent()
        content.title = "\(watch.name) cannot be checked"
        content.body = (watch.lastError ?? "The page could not be loaded.")
            + " This watch is not reporting on the page."
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }
}

@MainActor
private final class LoadWaiter: NSObject, WKNavigationDelegate {
    var onFinish: ((Error?) -> Void)?

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        onFinish?(nil)
        onFinish = nil
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        onFinish?(error)
        onFinish = nil
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        onFinish?(error)
        onFinish = nil
    }
}
