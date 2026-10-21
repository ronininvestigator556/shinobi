// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import Testing
import WebKit

@testable import CaptureKit

/// Exercised against a real `WKWebView` loading real markup, because every property that
/// matters here is a property of what WebKit does with the page, not of the script's text.
@Suite("Page archiving", .serialized)
@MainActor
struct PageArchiverTests {

    /// Loads markup and waits for it to finish, so the archiver sees a settled DOM.
    private func load(_ html: String) async throws -> WKWebView {
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 900, height: 700))
        let delegate = LoadWaiter()
        webView.navigationDelegate = delegate

        await withCheckedContinuation { continuation in
            delegate.onFinish = { continuation.resume() }
            webView.loadHTMLString(html, baseURL: URL(string: "https://archive.test/page")!)
        }
        // The archiver reads computed state; give the run loop a turn to settle.
        try await Task.sleep(for: .milliseconds(150))
        _ = delegate   // keep the delegate alive for the duration of the load
        return webView
    }

    // MARK: The reason this exists

    @Test("Collapsed and hidden content is archived")
    func hiddenContentSurvives() async throws {
        // The gap that motivated the whole serialiser. The text index uses innerText, which
        // omits anything not rendered — a Wikipedia infobox that collapsed on reload took its
        // contents out of the record with it. Serialising the DOM keeps them.
        let webView = try await load("""
            <html><body>
              <p>Visible paragraph</p>
              <details><summary>Show</summary><p>Concealed by a details element</p></details>
              <div style="display:none">Hidden by display none</div>
              <div hidden>Hidden by attribute</div>
            </body></html>
            """)

        let archive = try await PageArchiver.archive(webView)

        #expect(archive.html.contains("Concealed by a details element"))
        #expect(archive.html.contains("Hidden by display none"))
        #expect(archive.html.contains("Hidden by attribute"))

        // And confirm the old approach really would have lost them, so this test documents
        // the difference rather than merely asserting success.
        let rendered = try await webView.evaluateJavaScript("document.body.innerText") as? String
        #expect(rendered?.contains("Hidden by display none") == false)
    }

    // MARK: An exhibit must not execute

    @Test("Scripts and event handlers are removed")
    func archiveDoesNotExecute() async throws {
        let webView = try await load("""
            <html><body onload="void 0">
              <script>window.marker = 'inline script body';</script>
              <script src="https://archive.test/remote.js"></script>
              <button onclick="alert('handler')">Press</button>
              <a href="javascript:alert('href')">Link</a>
              <p>Ordinary content</p>
            </body></html>
            """)

        let archive = try await PageArchiver.archive(webView)

        // An archive is opened later, by other people, sometimes on machines that matter. It
        // must not be able to alter what it shows, phone home, or signal that it is being read.
        #expect(!archive.html.contains("<script"))
        #expect(!archive.html.contains("inline script body"))
        #expect(!archive.html.lowercased().contains("onclick"))
        #expect(!archive.html.lowercased().contains("onload"))
        #expect(!archive.html.lowercased().contains("javascript:"))

        #expect(archive.stats.scriptsRemoved >= 2)
        #expect(archive.stats.handlersRemoved >= 2)
        #expect(archive.notes.contains { $0.contains("does not execute") })

        // The page's actual content is untouched.
        #expect(archive.html.contains("Ordinary content"))
    }

    @Test("Password fields are not captured")
    func passwordsAreNotArchived() async throws {
        let webView = try await load("""
            <html><body>
              <input id="user" type="text">
              <input id="secret" type="password">
            </body></html>
            """)
        _ = try await webView.evaluateJavaScript("""
            document.getElementById('user').value = 'investigator';
            document.getElementById('secret').value = 'hunter2-should-not-appear';
            """)

        let archive = try await PageArchiver.archive(webView)

        // Form state is evidence, but a credential typed into a subject's login form is a
        // liability that should never reach a case file handed to anyone else.
        #expect(archive.html.contains("investigator"))
        #expect(!archive.html.contains("hunter2-should-not-appear"))
    }

    @Test("An archive makes no network references when opened")
    func archiveDoesNotPhoneHome() async throws {
        // Found on a real capture: Wikipedia's CentralAutoLogin 1x1 pixel failed to inline
        // and was left as a live remote src, so opening the exhibit months later would have
        // told the subject's server it was being reviewed, and from where. Stripping scripts
        // is not enough on its own.
        let webView = try await load("""
            <html><head>
              <link rel="preload" href="https://archive.invalid/font.woff2" as="font">
              <link rel="icon" href="https://archive.invalid/favicon.ico">
              <meta http-equiv="refresh" content="5;url=https://archive.invalid/next">
            </head><body>
              <img src="https://archive.invalid/tracker.gif?id=1" width="1" height="1">
              <iframe src="https://archive.invalid/frame"></iframe>
              <video poster="https://archive.invalid/poster.jpg"></video>
              <a href="https://archive.invalid/a-real-link">A link</a>
            </body></html>
            """)

        let archive = try await PageArchiver.archive(webView)

        // Nothing that loads by itself may remain. Matched with a leading space so these
        // do not accidentally match the data-shinobi-blocked-* attributes that record the
        // originals — an earlier version of this test passed by matching its own evidence
        // of success.
        #expect(!archive.html.contains(" src=\"http"))
        #expect(!archive.html.contains(" poster=\"http"))
        #expect(!archive.html.contains(" srcset=\"http"))
        #expect(!archive.html.contains("rel=\"preload\""))
        #expect(!archive.html.lowercased().contains("http-equiv=\"refresh\""))

        // But the original URLs are preserved, because what the page referenced is evidence.
        #expect(archive.html.contains("data-shinobi-blocked-src"))
        #expect(archive.html.contains("https://archive.invalid/tracker.gif?id=1"))

        // And ordinary links survive: they say where the page pointed and only load if a
        // reader chooses to follow them.
        #expect(archive.html.contains("href=\"https://archive.invalid/a-real-link\""))

        #expect(archive.stats.remoteReferencesNeutralised >= 4)
        #expect(archive.notes.contains { $0.contains("neutralised") })
    }

    @Test("Trackers hidden inside noscript are removed")
    func noscriptTrackersAreRemoved() async throws {
        // The case that defeated the first version of the sweep. While scripting is enabled a
        // browser keeps noscript content as a text node rather than parsing it, so it is
        // invisible to querySelectorAll while still present in the serialised markup — the
        // archive read as clean and would still have fired a request when opened with
        // JavaScript off.
        let webView = try await load("""
            <html><body>
              <p>Real content</p>
              <noscript><img src="https://archive.invalid/noscript-pixel.gif?id=1"></noscript>
            </body></html>
            """)

        let archive = try await PageArchiver.archive(webView)

        #expect(!archive.html.contains("noscript-pixel.gif"))
        #expect(!archive.html.contains("<noscript"))
        #expect(archive.stats.noscriptBlocksRemoved == 1)
        #expect(archive.html.contains("Real content"))
    }

    // MARK: Form and canvas state

    @Test("Form values as filled in are preserved")
    func formStateIsPreserved() async throws {
        let webView = try await load("""
            <html><body>
              <input id="t" type="text">
              <textarea id="a"></textarea>
              <input id="c" type="checkbox">
            </body></html>
            """)
        _ = try await webView.evaluateJavaScript("""
            document.getElementById('t').value = 'typed value';
            document.getElementById('a').value = 'area value';
            document.getElementById('c').checked = true;
            """)

        let archive = try await PageArchiver.archive(webView)

        // What the investigator saw includes what was in the fields; the raw markup has none
        // of it, because these live only as DOM properties.
        #expect(archive.html.contains("typed value"))
        #expect(archive.html.contains("area value"))
        #expect(archive.html.contains("checked"))
    }

    @Test("Canvas pixels are rasterised, since they replay blank without scripts")
    func canvasIsRasterised() async throws {
        let webView = try await load("<html><body><canvas id='c' width='40' height='40'></canvas></body></html>")
        _ = try await webView.evaluateJavaScript("""
            const ctx = document.getElementById('c').getContext('2d');
            ctx.fillStyle = '#ff0000';
            ctx.fillRect(0, 0, 40, 40);
            """)

        let archive = try await PageArchiver.archive(webView)

        #expect(archive.stats.canvasesRasterised == 1)
        #expect(archive.html.contains("data-shinobi-was=\"canvas\""))
        #expect(archive.html.contains("data:image/png;base64"))
    }

    // MARK: Honesty about fidelity

    @Test("A capture records provenance in the file itself")
    func archiveCarriesProvenance() async throws {
        let webView = try await load("<html><body><p>Content</p></body></html>")
        let archive = try await PageArchiver.archive(webView)

        // Someone opening this file months later, without Shinobi, should be able to see what
        // it is and how it was made.
        #expect(archive.html.hasPrefix("<!DOCTYPE html>"))
        #expect(archive.html.contains("Archived by Shinobi"))
        #expect(archive.html.contains("https://archive.test/page"))
        #expect(archive.html.contains("faithful reconstruction"))
    }

    @Test("A base element is inserted so relative links still resolve")
    func baseIsInserted() async throws {
        let webView = try await load("<html><body><a href='/relative/path'>Link</a></body></html>")
        let archive = try await PageArchiver.archive(webView)
        #expect(archive.html.contains("<base href=\"https://archive.test/page\""))
    }

    @Test("A clean page reports itself as complete")
    func cleanPageIsComplete() async throws {
        let webView = try await load("<html><body><p>Just text</p></body></html>")
        let archive = try await PageArchiver.archive(webView)
        #expect(archive.stats.isComplete)
    }

    @Test("An unreachable image is counted as a failure, not silently dropped")
    func failedResourcesAreCounted() async throws {
        let webView = try await load("""
            <html><body><img src="https://archive.invalid/nonexistent.png"></body></html>
            """)
        let archive = try await PageArchiver.archive(webView)

        // A silent partial capture is worse than an obviously partial one, because only the
        // second can be argued about honestly.
        #expect(archive.stats.imagesFailed >= 1)
        #expect(!archive.stats.isComplete)
        #expect(archive.notes.contains { $0.contains("could not be inlined") })
    }

    @Test("Inline styles are preserved so the archive still looks like the page")
    func stylesArePreserved() async throws {
        let webView = try await load("""
            <html><head><style>.flag { color: rgb(1, 2, 3); }</style></head>
            <body><p class="flag">Styled</p></body></html>
            """)
        let archive = try await PageArchiver.archive(webView)
        #expect(archive.html.contains("rgb(1, 2, 3)"))
    }
}

/// Bridges `WKNavigationDelegate` into async/await for the tests.
@MainActor
private final class LoadWaiter: NSObject, WKNavigationDelegate {
    var onFinish: (() -> Void)?

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        onFinish?()
        onFinish = nil
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        onFinish?()
        onFinish = nil
    }
}
