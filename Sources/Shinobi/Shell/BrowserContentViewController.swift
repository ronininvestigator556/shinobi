// SPDX-License-Identifier: GPL-3.0-or-later
import AppKit
import ShinobiKit
import WebKit

/// The centre pane: tab strip, web content, capture ledger.
@MainActor
final class BrowserContentViewController: NSViewController {

    let tabBar = TabBarView()
    let ledger = CaptureLedgerView()
    let findBar = FindBarView()
    private let webHost = NSView()
    private let progressBar = ProgressLineView()

    private var findBarHeight: NSLayoutConstraint!
    private weak var currentWebView: WKWebView?

    var isFindBarVisible: Bool { !findBar.isHidden }

    override func loadView() {
        view = NSView()
        view.wantsLayer = true
        view.setLayerBackground(Palette.windowBackground)

        webHost.wantsLayer = true
        webHost.setLayerBackground(Palette.windowBackground)

        findBar.isHidden = true

        for subview in [tabBar, findBar, webHost, progressBar, ledger] as [NSView] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(subview)
        }

        findBarHeight = findBar.heightAnchor.constraint(equalToConstant: 0)

        NSLayoutConstraint.activate([
            tabBar.topAnchor.constraint(equalTo: view.topAnchor),
            tabBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tabBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tabBar.heightAnchor.constraint(equalToConstant: TabBarView.barHeight),

            findBar.topAnchor.constraint(equalTo: tabBar.bottomAnchor),
            findBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            findBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            findBarHeight,

            // The progress line sits at the very top of the content area, where the eye
            // already is when a page is loading.
            progressBar.topAnchor.constraint(equalTo: findBar.bottomAnchor),
            progressBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            progressBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            progressBar.heightAnchor.constraint(equalToConstant: ProgressLineView.lineHeight),

            webHost.topAnchor.constraint(equalTo: findBar.bottomAnchor),
            webHost.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webHost.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            ledger.topAnchor.constraint(equalTo: webHost.bottomAnchor),
            ledger.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            ledger.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            ledger.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            ledger.heightAnchor.constraint(equalToConstant: CaptureLedgerView.ledgerHeight),
        ])
    }

    // MARK: Find bar

    func setFindBarVisible(_ visible: Bool) {
        findBar.isHidden = !visible
        findBarHeight.constant = visible ? FindBarView.barHeight : 0
        if visible { findBar.focus() }
    }

    // MARK: Progress

    func setProgress(_ progress: Double, isLoading: Bool) {
        progressBar.update(progress: progress, isLoading: isLoading)
    }

    /// Swaps the displayed web view.
    ///
    /// Views are detached rather than destroyed — the `BrowserTab` retains its own web view,
    /// so a backgrounded tab keeps its process, session and scroll position.
    func show(_ webView: WKWebView?) {
        guard currentWebView !== webView else { return }
        currentWebView?.removeFromSuperview()
        currentWebView = webView

        guard let webView else { return }
        webView.translatesAutoresizingMaskIntoConstraints = false
        webHost.addSubview(webView)
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: webHost.topAnchor),
            webView.leadingAnchor.constraint(equalTo: webHost.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: webHost.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: webHost.bottomAnchor),
        ])
    }
}


/// A hairline load indicator drawn across the top of the content area.
///
/// Preferred over a spinner in the toolbar: it conveys *how far along* a load is, which is
/// what tells an investigator whether a slow page is worth waiting on, and it costs two
/// pixels of chrome instead of a control.
@MainActor
final class ProgressLineView: NSView {

    static let lineHeight: CGFloat = 2

    private var progress: Double = 0
    private var isLoading: Bool = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(progress: Double, isLoading: Bool) {
        self.progress = progress
        self.isLoading = isLoading
        isHidden = !isLoading
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard isLoading else { return }
        Palette.accent.setFill()
        NSRect(x: 0, y: 0, width: bounds.width * progress, height: bounds.height).fill()
    }
}
