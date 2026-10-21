// SPDX-License-Identifier: GPL-3.0-or-later
import AppKit
import Combine
import IdentityKit
import ShinobiKit
import PivotKit
import WebKit

/// One tab: a `WKWebView` plus the observable state the shell draws around it.
///
/// A tab is created against a `WKWebViewConfiguration` supplied by its owner rather than
/// building its own. That is the seam Phase 1 needs: a identity will vend a configuration
/// carrying its own `WKWebsiteDataStore`, proxy, user agent and content rules, and the tab
/// will be permanently bound to whichever one it was born with. There is deliberately no
/// setter for the configuration — retargeting a live tab at a different identity is exactly
/// the class of mistake the identity model exists to make impossible.
@MainActor
final class BrowserTab: NSObject, Identifiable {

    let id = UUID()
    let webView: WKWebView

    /// The identity this tab operates as.
    ///
    /// `let`, and there is deliberately no way to change it. Retargeting a live tab at a
    /// different identity is the exact mistake the identity model exists to make
    /// impossible — a tab logged into a persona's account must never be able to become a
    /// tab in another persona's session. Switching identities opens a new tab instead.
    let identity: Identity

    /// Emitted *after* any chrome-visible property has changed.
    ///
    /// Deliberately not `@Published`. Combine's `@Published` publishes from `willSet`, so a
    /// subscriber that reads the model — as the chrome must, since it aggregates several
    /// properties across several tabs — sees the value from *before* the change. That made
    /// every tab title, window title and inspector field exactly one update stale. It hid
    /// for a long time because a title normally changes once per navigation, where being one
    /// behind is indistinguishable from being correct; it only became visible on a page that
    /// rewrote its own title and then stopped.
    let didChange = PassthroughSubject<Void, Never>()

    /// Load progress, separated because it fires continuously and drives only the thin
    /// progress line rather than a full chrome refresh.
    let progressDidChange = PassthroughSubject<Void, Never>()

    private(set) var title: String = "New Tab" { didSet { didChange.send() } }
    private(set) var url: URL? { didSet { didChange.send() } }
    private(set) var isLoading: Bool = false { didSet { didChange.send() } }
    private(set) var progress: Double = 0 { didSet { progressDidChange.send() } }
    /// Whether the page was served over TLS. Surfaced in the address field, and recorded
    /// with every capture from Phase 3 onward.
    private(set) var isSecure: Bool = false { didSet { didChange.send() } }
    private(set) var favicon: NSImage? { didSet { didChange.send() } }

    private var observations: [NSKeyValueObservation] = []
    private var faviconTask: Task<Void, Never>?

    /// Set the moment a load is asked for, before WebKit has told us anything.
    ///
    /// `url` and `isLoading` both arrive asynchronously through KVO, so a burst of calls —
    /// twelve addresses on the command line, or a rapid series of link openings — would all
    /// look at a still-blank tab and decide it was free to reuse. Twelve pages collapsed into
    /// one tab. This flag closes that window because it is set synchronously.
    private(set) var hasBeenAskedToLoad = false

    /// Called once a navigation has committed and the page has finished loading. The case
    /// recorder hangs off this.
    var onDidFinishNavigation: ((BrowserTab) -> Void)?

    /// The context of the last right-click, reported by the page.
    private(set) var contextTarget = ContextTarget()

    /// Builds the pivot items when the context menu is about to open.
    var pivotItemProvider: ((ContextTarget) -> [NSMenuItem])?

    init(configuration: WKWebViewConfiguration, identity: Identity) {
        // The context script and its message handler are registered once per identity by the
        // window controller, not here. A identity's content controller is shared by all its
        // tabs, and `WKUserContentController.add(_:name:)` raises an Objective-C exception
        // when a name is already registered — so doing it per tab meant the second tab in a
        // identity threw, unwound through init, and was swallowed by AppKit. New tabs simply
        // stopped appearing.
        self.webView = PivotingWebView(frame: .zero, configuration: configuration)
        self.identity = identity
        super.init()

        // Applied to the view rather than the configuration because that is where WebKit
        // exposes it. `nil` leaves WebKit's own string, which is the honest default: Shinobi
        // *is* Safari underneath, and claiming otherwise creates a mismatch between the
        // declared agent and observable engine behaviour.
        webView.customUserAgent = identity.userAgent.stringValue

        webView.navigationDelegate = self
        if let pivoting = webView as? PivotingWebView {
            pivoting.owner = self
        }
        webView.allowsBackForwardNavigationGestures = true
        webView.allowsMagnification = true
        // Draw the web view's own background dark so a page that has not painted yet does
        // not flash white against the surrounding chrome.
        webView.setValue(false, forKey: "drawsBackground")

        observe()
    }

    private func observe() {
        // KVO rather than the navigation delegate: title and URL change without a
        // navigation (pushState, SPA routing), and Shinobi's capture pipeline keys off the
        // URL actually showing in the address bar, not the last committed navigation.
        observations = [
            webView.observe(\.title, options: [.initial, .new]) { [weak self] webView, _ in
                MainActor.assumeIsolated {
                    let new = webView.title?.trimmingCharacters(in: .whitespacesAndNewlines)
                    self?.title = (new?.isEmpty == false) ? new! : (webView.url?.host ?? "New Tab")
                }
            },
            webView.observe(\.url, options: [.initial, .new]) { [weak self] webView, _ in
                MainActor.assumeIsolated {
                    self?.url = webView.url
                    self?.isSecure = webView.url?.scheme == "https"
                    if let host = webView.url?.host {
                        self?.favicon = FaviconLoader.cachedIcon(forHost: host)
                    } else {
                        self?.favicon = nil
                    }
                }
            },
            webView.observe(\.isLoading, options: [.initial, .new]) { [weak self] webView, _ in
                MainActor.assumeIsolated { self?.isLoading = webView.isLoading }
            },
            webView.observe(\.estimatedProgress, options: [.initial, .new]) { [weak self] webView, _ in
                MainActor.assumeIsolated { self?.progress = webView.estimatedProgress }
            },
        ]
    }

    // MARK: Navigation

    /// Loads a user-typed string, resolving it as a URL or handing it to a search engine.
    func load(userInput: String) {
        guard let url = URLResolver.resolve(userInput) else { return }
        load(url)
    }

    func load(_ url: URL) {
        hasBeenAskedToLoad = true
        webView.load(URLRequest(url: url))
    }

    func reload() {
        // Bypass the cache. An investigator reloading is almost always asking "is it still
        // there / has it changed", and a cache hit answers a different question.
        webView.reloadFromOrigin()
    }

    func stop() { webView.stopLoading() }
    func goBack() { webView.goBack() }
    func goForward() { webView.goForward() }

    func updateContextTarget(_ target: ContextTarget) { contextTarget = target }

    var canGoBack: Bool { webView.canGoBack }
    var canGoForward: Bool { webView.canGoForward }

    // MARK: Zoom

    /// Page zoom, clamped to a range that stays readable in both directions.
    func adjustZoom(by delta: CGFloat) {
        webView.pageZoom = min(3.0, max(0.5, webView.pageZoom + delta))
    }

    func resetZoom() { webView.pageZoom = 1.0 }
}

extension BrowserTab: WKNavigationDelegate {

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        onDidFinishNavigation?(self)

        // Supersede any in-flight lookup: a fast navigation should not have an earlier
        // page's icon land on top of the current one.
        faviconTask?.cancel()
        faviconTask = Task { [weak self] in
            guard let self else { return }
            let icon = await FaviconLoader.load(from: self.webView)
            guard !Task.isCancelled, let icon else { return }
            self.favicon = icon
        }
    }
}


/// A web view that adds Shinobi's pivot items to the page context menu.
///
/// Subclassing is the only route on macOS: `WKUIDelegate`'s context-menu hooks are iOS-only,
/// and `willOpenMenu` is where AppKit hands a view its own menu before it is shown.
@MainActor
final class PivotingWebView: WKWebView {
    weak var owner: BrowserTab?

    override func willOpenMenu(_ menu: NSMenu, with event: NSEvent) {
        super.willOpenMenu(menu, with: event)
        guard let owner, let items = owner.pivotItemProvider?(owner.contextTarget), !items.isEmpty
        else { return }

        // Prepended rather than appended: the pivot is the reason an investigator opened this
        // menu, and burying it under WebKit's standard entries would make it slower to use
        // than copying the value and pasting it into a browser.
        menu.insertItem(.separator(), at: 0)
        for (offset, item) in items.enumerated() {
            menu.insertItem(item, at: offset)
        }
    }

    override func didCloseMenu(_ menu: NSMenu, with event: NSEvent?) {
        super.didCloseMenu(menu, with: event)
        ActionProxy.shared.clear()
    }
}

/// Receives the context-menu report from a identity's pages.
///
/// One relay per identity rather than per tab, because the content controller is shared and
/// a script message name can only be registered once on it. The message carries the web view
/// it came from, which is how the report reaches the right tab.
@MainActor
final class ContextMessageRelay: NSObject, WKScriptMessageHandler {

    /// Resolves a web view to the tab that owns it.
    var resolveTab: ((WKWebView) -> BrowserTab?)?

    nonisolated func userContentController(
        _ controller: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard let body = message.body as? [String: Any] else { return }
        let target = ContextTarget(message: body)
        MainActor.assumeIsolated {
            guard let webView = message.webView, let tab = resolveTab?(webView) else { return }
            tab.updateContextTarget(target)
        }
    }
}
