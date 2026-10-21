// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import Testing
import WebKit

@testable import PivotKit

@Suite("Page analysis", .serialized)
@MainActor
struct PageAnalysisTests {

    private func analyse(_ html: String) async throws -> PageAnalysis {
        let webView = WKWebView(frame: .init(x: 0, y: 0, width: 900, height: 700))
        let waiter = Waiter()
        webView.navigationDelegate = waiter
        await withCheckedContinuation { continuation in
            waiter.onFinish = { continuation.resume() }
            webView.loadHTMLString(html, baseURL: URL(string: "https://subject.test/page")!)
        }
        try await Task.sleep(for: .milliseconds(150))

        let payload = try await webView.callAsyncJavaScript(
            PageAnalyserScript.source,
            arguments: ["maxLinks": 2000, "maxEmails": 500, "maxImages": 500],
            contentWorld: .defaultClient
        ) as? [String: Any]
        _ = waiter
        return PageAnalysis(payload: payload ?? [:])
    }

    @Test("Links are harvested and split by origin")
    func linksAreHarvested() async throws {
        let analysis = try await analyse("""
            <html><body>
              <a href="/internal">Internal page</a>
              <a href="https://other.test/a">Somewhere else</a>
              <a href="https://other.test/b">Also elsewhere</a>
            </body></html>
            """)

        #expect(analysis.links.count == 3)
        #expect(analysis.links.filter(\.isExternal).count == 2)
        // "Who does this site point at" is usually the question, so hosts are grouped.
        #expect(analysis.linksByHost.first?.host == "other.test")
        #expect(analysis.linksByHost.first?.links.count == 2)
    }

    @Test("Link text is kept, since it is often the identifying part")
    func linkTextIsKept() async throws {
        let analysis = try await analyse(
            "<html><body><a href='https://other.test/x'>Companies House filing</a></body></html>")
        #expect(analysis.links.first?.text == "Companies House filing")
    }

    @Test("Addresses are harvested from links and from text")
    func emailsAreHarvested() async throws {
        let analysis = try await analyse("""
            <html><body>
              <a href="mailto:linked@example.com?subject=hi">Write to us</a>
              <p>Or reach the registrant at Written@Example.com directly.</p>
            </body></html>
            """)

        #expect(analysis.emails.contains("linked@example.com"))
        // Lowercased, so the same address written two ways is one address.
        #expect(analysis.emails.contains("written@example.com"))
    }

    @Test("A repeated link is listed once")
    func linksAreDeduplicated() async throws {
        let analysis = try await analyse("""
            <html><body>
              <a href="https://other.test/same">One</a>
              <a href="https://other.test/same">Two</a>
            </body></html>
            """)
        #expect(analysis.links.filter { $0.url.contains("/same") }.count == 1)
    }

    @Test("Hosts the page loads from are recorded, not only ones it links to")
    func externalHostsIncludeAssets() async throws {
        // Where a page fetches from says more about who is involved than where it links.
        let analysis = try await analyse("""
            <html><head><script src="https://cdn.other.test/a.js"></script></head>
            <body><img src="https://images.other.test/p.png"></body></html>
            """)
        #expect(analysis.externalHosts.contains("cdn.other.test"))
        #expect(analysis.externalHosts.contains("images.other.test"))
    }

    // MARK: Fingerprinting

    @Test("Technologies are detected with the evidence for each")
    func technologiesAreDetected() async throws {
        let analysis = try await analyse("""
            <html><head>
              <meta name="generator" content="WordPress 6.5">
              <link rel="stylesheet" href="/wp-content/themes/x/style.css">
              <script src="https://www.googletagmanager.com/gtag/js?id=G-1"></script>
            </head><body><div id="__next">app</div></body></html>
            """)

        let names = Set(analysis.technologies.map(\.name))
        #expect(names.contains("WordPress"))
        #expect(names.contains("Google Analytics"))
        #expect(names.contains("Next.js"))

        // A fingerprint is an inference, so what was observed travels with the claim and an
        // investigator can judge it rather than take it on trust.
        let wordpress = try #require(analysis.technologies.first { $0.name == "WordPress" })
        #expect(!wordpress.evidence.isEmpty)
    }

    @Test("A plain page reports no technologies rather than guessing")
    func plainPageDetectsNothing() async throws {
        let analysis = try await analyse("<html><body><p>Just words.</p></body></html>")
        // Naming a stack that is not there is worse than naming none: an investigator may act
        // on it.
        #expect(analysis.technologies.isEmpty)
    }

    @Test("One broken rule does not abandon the analysis")
    func analysisIsResilient() async throws {
        // Every rule runs inside its own try/catch, so a page that breaks one still yields
        // links, addresses and the rest.
        let analysis = try await analyse("""
            <html><body>
              <a href="https://other.test/a">Link</a>
              <script>Object.defineProperty(window, 'Shopify', {
                get() { throw new Error('hostile'); } });</script>
            </body></html>
            """)
        #expect(!analysis.links.isEmpty)
    }

    @Test("Harvesting is bounded")
    func harvestingIsBounded() async throws {
        let anchors = (0..<50).map { "<a href='https://other.test/\($0)'>l\($0)</a>" }.joined()
        let webView = WKWebView(frame: .init(x: 0, y: 0, width: 800, height: 600))
        let waiter = Waiter()
        webView.navigationDelegate = waiter
        await withCheckedContinuation { continuation in
            waiter.onFinish = { continuation.resume() }
            webView.loadHTMLString("<html><body>\(anchors)</body></html>",
                                   baseURL: URL(string: "https://subject.test/")!)
        }
        try await Task.sleep(for: .milliseconds(150))

        // A page listing tens of thousands of links must not produce a panel that long.
        let payload = try await webView.callAsyncJavaScript(
            PageAnalyserScript.source,
            arguments: ["maxLinks": 10, "maxEmails": 10, "maxImages": 10],
            contentWorld: .defaultClient) as? [String: Any]
        _ = waiter
        #expect(PageAnalysis(payload: payload ?? [:]).links.count == 10)
    }
}

@Suite("Archive lookup")
struct ArchiveLookupTests {

    @Test("Wayback timestamps are parsed as UTC")
    func timestampsParse() throws {
        let date = try #require(ArchiveLookup.parseWaybackTimestamp("20260908114530"))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "UTC"))
        let parts = calendar.dateComponents([.year, .month, .day, .hour], from: date)
        #expect(parts.year == 2026)
        #expect(parts.month == 9)
        #expect(parts.day == 8)
        #expect(parts.hour == 11)
    }

    @Test("Malformed timestamps are rejected", arguments: ["", "2026", "not-a-date", "202609081145301"])
    func malformedTimestampsRejected(_ raw: String) {
        #expect(ArchiveLookup.parseWaybackTimestamp(raw) == nil)
    }

    @Test("Browsable services are offered for any page")
    func servicesAreOffered() throws {
        let page = try #require(URL(string: "https://subject.test/x?a=1"))
        let services = ArchiveLookup.browsableServices(for: page)
        #expect(services.contains { $0.service.contains("archive.today") })
        // Memento's aggregator was removed when timetravel.mementoweb.org stopped
        // responding. Offering a check that cannot complete is worse than not offering it,
        // because a silent failure reads as "nothing was archived".
        #expect(!services.contains { $0.service.contains("Memento") })
        #expect(services.allSatisfy { !$0.url.isEmpty })
    }

    @Test("The save request is a separate, deliberate action")
    func savingIsSeparate() throws {
        // Archiving is not looking up: it tells the Internet Archive to fetch the page, and
        // the capture is public and permanent. It must never happen as a side effect of a
        // lookup.
        let page = try #require(URL(string: "https://subject.test/x"))
        let url = try #require(ArchiveLookup.saveRequestURL(for: page))
        #expect(url.absoluteString.contains("/save/"))
    }
}

@MainActor
private final class Waiter: NSObject, WKNavigationDelegate {
    var onFinish: (() -> Void)?
    func webView(_ w: WKWebView, didFinish n: WKNavigation!) { onFinish?(); onFinish = nil }
    func webView(_ w: WKWebView, didFail n: WKNavigation!, withError e: Error) { onFinish?(); onFinish = nil }
}
