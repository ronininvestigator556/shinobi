// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import Testing

@testable import ShinobiKit

/// The address bar is a leak surface.
///
/// Every input that Shinobi hands to a search engine instead of navigating tells that search
/// engine what an investigator is looking at. For a tool whose users are researching people
/// who may be motivated to find out they are being researched, that is a real exposure, so
/// the navigate-versus-search boundary is pinned down here rather than left to feel.
@Suite("URL resolution")
struct URLResolverTests {

    // MARK: Inputs that must navigate

    @Test("Explicit schemes are taken at their word", arguments: [
        "https://example.com",
        "http://example.com",
        "file:///Users/investigator/case.html",
        "about:blank",
    ])
    func explicitSchemesPassThrough(_ input: String) throws {
        let url = try #require(URLResolver.resolve(input))
        #expect(url.absoluteString == input)
    }

    @Test("Bare hosts navigate rather than search", arguments: [
        "example.com",
        "example.co.uk",
        "sub.domain.example.org",
        "example.com/path/to/thing",
        "example.com:8443",
        "example.com/search?q=term",
    ])
    func bareHostsNavigate(_ input: String) throws {
        let url = try #require(URLResolver.resolve(input))
        #expect(url.scheme == "https")
        #expect(!isSearch(url), "\(input) leaked to a search engine")
    }

    @Test("IP addresses navigate", arguments: ["192.168.1.1", "10.0.0.1", "8.8.8.8", "255.255.255.255"])
    func ipAddressesNavigate(_ input: String) throws {
        let url = try #require(URLResolver.resolve(input))
        #expect(url.host == input)
        #expect(!isSearch(url), "\(input) leaked to a search engine")
    }

    @Test("localhost and onion addresses navigate")
    func specialHostsNavigate() throws {
        // An onion address reaching a clearnet search engine would be a serious disclosure.
        let onion = try #require(URLResolver.resolve("expyuzz4wqqyqhjn.onion"))
        #expect(!isSearch(onion))
        #expect(onion.host == "expyuzz4wqqyqhjn.onion")

        let local = try #require(URLResolver.resolve("localhost:8080"))
        #expect(!isSearch(local))
    }

    // MARK: Inputs that must search

    @Test("Prose searches", arguments: [
        "john smith birmingham",
        "who owns example",
        "site:example.com invoice",
    ])
    func proseSearches(_ input: String) throws {
        let url = try #require(URLResolver.resolve(input))
        #expect(isSearch(url), "\(input) was treated as an address")
    }

    @Test("Dotless single words search rather than resolving as a host")
    func dotlessWordsSearch() throws {
        // Without this, a typo'd single word would attempt a DNS lookup for an intranet
        // host and, on many networks, hit a wildcard resolver.
        let url = try #require(URLResolver.resolve("durham"))
        #expect(isSearch(url))
    }

    @Test("A numeric TLD is not a host")
    func numericTLDSearches() throws {
        // Guards the IPv4 check: 1.2.3 is neither a valid address nor a plausible host.
        let url = try #require(URLResolver.resolve("1.2.3"))
        #expect(isSearch(url))
    }

    @Test("Out-of-range octets are not treated as an IP address")
    func invalidIPFallsThrough() throws {
        let url = try #require(URLResolver.resolve("999.1.1.1"))
        #expect(isSearch(url))
    }

    @Test("javascript: URLs are not navigated to")
    func javascriptURLsDoNotExecute() throws {
        // Pasting a `javascript:` URL into the address bar is a classic self-XSS vector,
        // and an investigator pasting an unfamiliar string out of a subject's page is
        // exactly the scenario. It is not an allowed scheme, so it falls through to search.
        let url = try #require(URLResolver.resolve("javascript:alert(document.cookie)"))
        #expect(url.scheme != "javascript")
        #expect(isSearch(url))
    }

    // MARK: Empty input

    @Test("Blank input resolves to nothing", arguments: ["", "   ", "\n\t "])
    func blankInputIsIgnored(_ input: String) {
        #expect(URLResolver.resolve(input) == nil)
    }

    // MARK: Helper

    private func isSearch(_ url: URL) -> Bool {
        url.host?.contains("duckduckgo") == true
    }
}
