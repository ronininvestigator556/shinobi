// SPDX-License-Identifier: GPL-3.0-or-later
import AppKit
import CaptureKit
import CaseKit
import PivotKit
import Combine
import IdentityKit
import Foundation
import WebKit

/// Owns the case that is currently open, and records what the investigator looks at.
///
/// Recording is passive. When a case is open every page that finishes loading is written to
/// it, with no button to press. That is the whole lesson of the tools investigators already
/// rely on: a capture step you have to remember is a capture step you will forget, and you
/// will forget it on the page that mattered.
@MainActor
final class CaseController {

    private(set) var store: CaseStore?
    private(set) var visitCount: Int = 0

    /// Digest of the text recorded for each URL in this session, so the inspector can show
    /// the real hash of a real artifact rather than a placeholder.
    private var digestsByURL: [String: String] = [:]

    /// Artifacts captured for each URL in this session.
    private var artifactsByURL: [String: [Artifact]] = [:]

    /// What is currently being captured, for the ledger.
    private(set) var captureInProgress: String?

    /// How much of the session is preserved. Persisted, because a mode that silently reset to
    /// "capture everything" between launches would defeat the point of choosing another, and
    /// one that silently reset to "paused" would be dangerous.
    var captureMode: CaptureMode {
        get {
            UserDefaults.standard.string(forKey: Self.modeKey)
                .flatMap(CaptureMode.init(rawValue:)) ?? .continuous
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: Self.modeKey)
            didChange.send()
        }
    }

    private static let modeKey = "com.shinobi.browser.captureMode"

    /// Pages whose exhibits were captured on request, so the interface can show which are
    /// marked and which are only logged.
    private var exhibitURLs: Set<String> = []

    func hasExhibits(for url: URL) -> Bool { exhibitURLs.contains(url.absoluteString) }

    /// Fires whenever the open case changes, or a visit is recorded.
    let didChange = PassthroughSubject<Void, Never>()

    /// Reports a recording failure. A case that silently stops recording would be the worst
    /// possible failure mode, so this is surfaced rather than swallowed.
    var onRecordingFailure: ((Error) -> Void)?

    var isOpen: Bool { store != nil }
    var casePath: String? { store?.bundle.url.path }
    var caseName: String? { store?.bundle.displayName }

    // MARK: Lifecycle

    func create(at url: URL, name: String, reference: String?) throws {
        let bundle = try CaseBundle.create(at: url)
        let store = try CaseStore(bundle: bundle)
        try store.initialise(name: name, reference: reference)
        adopt(store)
    }

    func open(at url: URL) throws {
        let store = try CaseStore(bundle: try CaseBundle.open(at: url))
        try store.recordOpened()
        adopt(store)
    }

    /// Writes and signs the manifest.
    @discardableResult
    func writeManifest() throws -> CaseManifest {
        guard let store else { throw CaseError.noCaseOpen }
        return try store.writeManifest()
    }

    func export(to destination: URL, exhibitsOnly: Bool = false) throws -> CaseExport.Summary {
        guard let store else { throw CaseError.noCaseOpen }
        return try CaseExport(store: store, exhibitsOnly: exhibitsOnly).write(to: destination)
    }

    func timestampManifest() async throws -> Date {
        guard let store else { throw CaseError.noCaseOpen }
        return try await store.timestampManifest()
    }

    var hasTimestamp: Bool { store?.hasTimestamp ?? false }

    func verifyManifest() throws -> CaseStore.ManifestVerification {
        guard let store else { throw CaseError.noCaseOpen }
        return try store.verifyManifest()
    }

    func close() {
        // Sign on the way out, so a case put away is a case a recipient can check. Failing
        // to sign must not prevent closing — an unsigned case is still a case.
        try? store?.writeManifest()
        store = nil
        visitCount = 0
        digestsByURL.removeAll()
        artifactsByURL.removeAll()
        didChange.send()
    }

    func recordedDigest(for url: URL) -> String? {
        digestsByURL[url.absoluteString]
    }

    func artifacts(for url: URL) -> [Artifact] {
        artifactsByURL[url.absoluteString] ?? []
    }

    private func adopt(_ store: CaseStore) {
        self.store = store
        digestsByURL.removeAll()
        artifactsByURL.removeAll()
        visitCount = (try? store.visitCount()) ?? 0
        didChange.send()
    }

    // MARK: Recording

    /// Records a finished page load into the open case.
    ///
    /// Does nothing when no case is open — browsing outside a case is ordinary browsing, and
    /// must not quietly accumulate a record somewhere.
    func record(_ tab: BrowserTab) {
        guard captureMode.recordsVisits else { return }
        guard let store, let url = tab.url else { return }

        // `about:` and `file:` pages are chrome and local scratch, not evidence about a
        // subject. Recording them would clutter the log without adding anything.
        guard let scheme = url.scheme, scheme == "http" || scheme == "https" else { return }

        let identity = tab.identity
        let title = tab.title
        let secure = tab.isSecure
        let webView = tab.webView

        Task { [weak self] in
            guard let self else { return }
            self.captureInProgress = url.host ?? url.absoluteString
            self.didChange.send()
            defer {
                self.captureInProgress = nil
                self.didChange.send()
            }

            let text = await PageTextExtractor.extract(from: webView)

            // The page may have navigated away while text was being extracted; recording the
            // new page's content against the old URL would be a quietly false record.
            guard webView.url == url else { return }

            let recorded: CaseStore.RecordedVisit
            do {
                recorded = try store.record(
                    url: url.absoluteString,
                    title: title,
                    containerID: identity.id.uuidString,
                    containerName: identity.name,
                    secure: secure,
                    text: text
                )
            } catch {
                self.onRecordingFailure?(error)
                return
            }

            if let digest = recorded.textDigest {
                self.digestsByURL[url.absoluteString] = digest
            }
            self.visitCount = (try? store.visitCount()) ?? 0
            self.didChange.send()

            guard self.captureMode.capturesExhibitsAutomatically else {
                // The page is logged and searchable; the exhibits wait to be asked for.
                self.artifactsByURL[url.absoluteString] =
                    (try? store.artifacts(forVisit: recorded.id)) ?? []
                self.didChange.send()
                return
            }

            await self.captureArtifacts(
                for: recorded.id,
                url: url,
                webView: webView,
                text: text,
                store: store
            )
            self.exhibitURLs.insert(url.absoluteString)
        }
    }

    /// Captures the full set of exhibits for the page on screen, whatever the mode.
    ///
    /// Works in `paused` too: an investigator who has paused recording and then finds the page
    /// that matters should be able to keep it without first hunting through a menu to turn
    /// recording back on.
    func captureNow(_ tab: BrowserTab, completion: @escaping (Result<Int, Error>) -> Void) {
        guard let store else {
            completion(.failure(CaseError.noCaseOpen))
            return
        }
        guard let url = tab.url, let scheme = url.scheme, scheme == "http" || scheme == "https" else {
            completion(.failure(CaptureError.notCapturable))
            return
        }

        let identity = tab.identity
        let webView = tab.webView

        Task { [weak self] in
            guard let self else { return }
            self.captureInProgress = url.host ?? url.absoluteString
            self.didChange.send()
            defer {
                self.captureInProgress = nil
                self.didChange.send()
            }

            let text = await PageTextExtractor.extract(from: webView)

            // Reuse the visit recorded a moment ago if this page is already logged, rather
            // than creating a second visit for the same page view.
            let visitID: Int64
            if let existing = try? store.mostRecentVisit(for: url.absoluteString), existing.hasExhibits == false {
                visitID = existing.id
            } else {
                guard let recorded = try? store.record(
                    url: url.absoluteString,
                    title: tab.title,
                    containerID: identity.id.uuidString,
                    containerName: identity.name,
                    secure: tab.isSecure,
                    text: text
                ) else {
                    completion(.failure(CaptureError.couldNotRecord))
                    return
                }
                visitID = recorded.id
                if let digest = recorded.textDigest { self.digestsByURL[url.absoluteString] = digest }
            }

            await self.captureArtifacts(
                for: visitID,
                url: url,
                webView: webView,
                text: text,
                store: store
            )
            self.exhibitURLs.insert(url.absoluteString)
            self.visitCount = (try? store.visitCount()) ?? 0
            self.didChange.send()
            completion(.success(self.artifactsByURL[url.absoluteString]?.count ?? 0))
        }
    }

    enum CaptureError: Error, LocalizedError {
        case notCapturable
        case couldNotRecord

        var errorDescription: String? {
            switch self {
            case .notCapturable: "Only web pages can be captured."
            case .couldNotRecord: "The page could not be written to the case."
            }
        }
    }

    /// Captures the artifacts that require the page to still be loaded.
    ///
    /// Runs in order and re-checks the URL between steps. An investigator who clicks through
    /// quickly will navigate away mid-capture; when that happens the artifacts already taken
    /// are kept and the rest are simply absent, which the artifact list makes visible. The
    /// alternative — blocking navigation until capture finishes — would make the browser feel
    /// broken and would train people to disable capture.
    private func captureArtifacts(
        for visitID: Int64,
        url: URL,
        webView: WKWebView,
        text: String?,
        store: CaseStore
    ) async {
        var captured: [Artifact] = []

        func attach(_ kind: Artifact.Kind, _ data: Data, note: String?) {
            do {
                captured.append(try store.attach(kind, data: data, to: visitID, note: note))
                self.artifactsByURL[url.absoluteString] = captured
                self.didChange.send()
            } catch {
                self.onRecordingFailure?(error)
            }
        }

        // The text artifact is written by `record` itself, so it is not attached again here.
        captured = (try? store.artifacts(forVisit: visitID)) ?? []
        artifactsByURL[url.absoluteString] = captured

        guard webView.url == url else { return }
        if let archive = try? await PageArchiver.archive(webView) {
            let note = archive.notes.isEmpty
                ? "Scripts removed; resources inlined"
                : archive.notes.joined(separator: " ")
            attach(.archive, archive.data, note: note)
        }

        guard webView.url == url else { return }
        if let snapshot = try? await PageSnapshotter.screenshot(of: webView) {
            attach(
                .screenshot,
                snapshot.png,
                note: snapshot.truncated
                    ? "Page exceeded the capture height; the image is cut short"
                    : "Full page"
            )
        }

        guard webView.url == url else { return }
        if let pdf = try? await PageSnapshotter.pdf(of: webView) {
            attach(.pdf, pdf, note: nil)
        }

        // Transcribe the screenshot last, off the captured bytes rather than the live page,
        // so it costs nothing if the investigator has already navigated away.
        if let screenshot = captured.first(where: { $0.artifactKind == .screenshot }),
           let pixels = try? store.bundle.blobStore.data(for: screenshot.digest),
           let reading = try? TextRecognition.recognise(in: pixels),
           !reading.isEmpty {
            attach(.ocr, Data(reading.text.utf8), note: reading.note)
            // Indexed against the same visit, so a name that exists only in an image becomes
            // searchable alongside the page's own words.
            try? store.index(additionalText: reading.text, forVisit: visitID)
        }
    }

    // MARK: Queries

    func search(_ query: String) -> [SearchHit] {
        (try? store?.search(query)) ?? []
    }

    func verify() throws -> CaseStore.IntegrityReport {
        guard let store else { throw CaseError.noCaseOpen }
        return try store.verify()
    }

    func addNote(_ body: String) throws {
        guard let store else { throw CaseError.noCaseOpen }
        try store.addNote(body)
        didChange.send()
    }
}
