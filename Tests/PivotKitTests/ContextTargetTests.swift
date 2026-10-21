// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import Testing
import WebKit

@testable import PivotKit

/// The context script is the piece most likely to be quietly wrong: WebKit tells a macOS host
/// nothing about what was right-clicked, so everything the pivot menu offers depends on this
/// script reading the page correctly. Exercised against a real `WKWebView` with real events.
@Suite("Context targeting", .serialized)
@MainActor
struct ContextTargetTests {

    /// Loads markup, dispatches a `contextmenu` event at `selector`, and returns what the
    /// script reported.
    private func target(in html: String, rightClicking selector: String, selecting: String? = nil) async throws -> ContextTarget {
        let configuration = WKWebViewConfiguration()
        let collector = Collector()
        configuration.userContentController.add(collector, name: ContextTarget.messageName)
        configuration.userContentController.addUserScript(ContextTarget.script)

        let webView = WKWebView(frame: .init(x: 0, y: 0, width: 800, height: 600),
                                configuration: configuration)
        let waiter = LoadWaiter()
        webView.navigationDelegate = waiter
        await withCheckedContinuation { continuation in
            waiter.onFinish = { continuation.resume() }
            webView.loadHTMLString(html, baseURL: URL(string: "https://pivot.test/page")!)
        }
        try await Task.sleep(for: .milliseconds(120))

        if let selecting {
            _ = try? await webView.evaluateJavaScript("""
                const node = document.querySelector('\(selecting)');
                const range = document.createRange();
                range.selectNodeContents(node);
                const selection = window.getSelection();
                selection.removeAllRanges();
                selection.addRange(range);
                """)
        }

        _ = try? await webView.evaluateJavaScript("""
            document.querySelector('\(selector)').dispatchEvent(
                new MouseEvent('contextmenu', { bubbles: true, cancelable: true }));
            """)
        try await Task.sleep(for: .milliseconds(120))

        _ = waiter
        return collector.latest
    }

    @Test("A right-click on an image reports the image")
    func imageIsReported() async throws {
        let result = try await target(
            in: "<html><body><img id='pic' src='https://pivot.test/photo.jpg'></body></html>",
            rightClicking: "#pic")
        #expect(result.imageURL == "https://pivot.test/photo.jpg")
    }

    @Test("A right-click on a link reports its address and its text")
    func linkIsReported() async throws {
        let result = try await target(
            in: "<html><body><a id='a' href='https://target.test/x'>The registrant</a></body></html>",
            rightClicking: "#a")
        #expect(result.linkURL == "https://target.test/x")
        #expect(result.linkText == "The registrant")
    }

    @Test("An image inside a link reports both")
    func imageInsideLinkReportsBoth() async throws {
        // Hit-testing from the host gets this wrong: whichever of the two it resolves to, the
        // other is lost. `closest()` from the clicked node finds both.
        let result = try await target(
            in: """
            <html><body><a id='a' href='https://target.test/profile'>
              <img id='pic' src='https://pivot.test/avatar.jpg'></a></body></html>
            """,
            rightClicking: "#pic")
        #expect(result.imageURL == "https://pivot.test/avatar.jpg")
        #expect(result.linkURL == "https://target.test/profile")
    }

    @Test("A right-click on a nested element still finds the enclosing link")
    func nestedElementFindsLink() async throws {
        let result = try await target(
            in: "<html><body><a href='https://target.test/y'><span id='s'><b>deep</b></span></a></body></html>",
            rightClicking: "#s")
        #expect(result.linkURL == "https://target.test/y")
    }

    @Test("The current selection is reported")
    func selectionIsReported() async throws {
        let result = try await target(
            in: "<html><body><p id='p'>8.8.8.8</p><div id='d'>elsewhere</div></body></html>",
            rightClicking: "#d", selecting: "#p")
        #expect(result.selection == "8.8.8.8")
    }

    @Test("A page that blocks the context menu is still reported on")
    func pageCannotSuppressReporting() async throws {
        // Registered in the capture phase precisely because plenty of sites call
        // preventDefault on contextmenu — and those are the sites an investigator most needs
        // the pivot menu on.
        let result = try await target(
            in: """
            <html><body>
            <script>document.addEventListener('contextmenu', e => e.stopPropagation(), true);</script>
            <a id='a' href='https://target.test/z'>blocked</a></body></html>
            """,
            rightClicking: "#a")
        #expect(result.linkURL == "https://target.test/z")
    }

    @Test("A click on nothing in particular reports nothing")
    func emptyTargetIsEmpty() async throws {
        let result = try await target(
            in: "<html><body><div id='d'>plain</div></body></html>",
            rightClicking: "#d")
        #expect(result.isEmpty)
    }
}

@MainActor
private final class Collector: NSObject, WKScriptMessageHandler {
    var latest = ContextTarget()

    nonisolated func userContentController(
        _ controller: WKUserContentController, didReceive message: WKScriptMessage
    ) {
        guard let body = message.body as? [String: Any] else { return }
        MainActor.assumeIsolated { latest = ContextTarget(message: body) }
    }
}

@MainActor
private final class LoadWaiter: NSObject, WKNavigationDelegate {
    var onFinish: (() -> Void)?
    func webView(_ w: WKWebView, didFinish n: WKNavigation!) { onFinish?(); onFinish = nil }
    func webView(_ w: WKWebView, didFail n: WKNavigation!, withError e: Error) { onFinish?(); onFinish = nil }
}
