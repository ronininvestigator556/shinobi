// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import Testing
import WebKit

@testable import IdentityKit

/// The central Phase 1 guarantee: two identities cannot see each other's session.
///
/// This is asserted against the real WebKit data stores rather than a stand-in. The whole
/// claim Shinobi makes about compartmentalisation rests on `WKWebsiteDataStore(forIdentifier:)`
/// actually separating cookie jars, so the test exercises exactly that — if a future change
/// accidentally routed two identities at one store, or fell back to `.default()`, this fails.
@Suite("Identity isolation", .serialized)
@MainActor
struct IsolationTests {

    private func makeCookie(name: String, value: String) throws -> HTTPCookie {
        try #require(HTTPCookie(properties: [
            .domain: "isolation.test",
            .path: "/",
            .name: name,
            .value: value,
            .secure: "FALSE",
            .expires: Date().addingTimeInterval(3600),
        ]))
    }

    @Test("A cookie set in one identity is invisible to another")
    func cookiesDoNotCross() async throws {
        let provider = IdentitySessionProvider()
        let alice = Identity(name: "Alice", color: .blue)
        let bob = Identity(name: "Bob", color: .green)

        let aliceStore = try provider.configuration(for: alice).websiteDataStore
        let bobStore = try provider.configuration(for: bob).websiteDataStore

        defer {
            Task {
                await provider.destroySession(for: alice)
                await provider.destroySession(for: bob)
            }
        }

        // The two identities must not even be backed by the same object.
        #expect(aliceStore !== bobStore)

        try await aliceStore.httpCookieStore.setCookie(makeCookie(name: "session", value: "alice-secret"))

        let aliceCookies = await aliceStore.httpCookieStore.allCookies()
        let bobCookies = await bobStore.httpCookieStore.allCookies()

        #expect(aliceCookies.contains { $0.name == "session" && $0.value == "alice-secret" })
        // The assertion the product is built on: a persona's session never reaches another.
        #expect(!bobCookies.contains { $0.name == "session" })
    }

    @Test("The same identity returns the same store")
    func sameContainerSharesOneStore() throws {
        let provider = IdentitySessionProvider()
        let identity = Identity(name: "Stable", color: .cyan)
        defer { Task { await provider.destroySession(for: identity) } }

        // Tabs in one identity must share a session, or a persona would be logged out
        // every time it opened a second tab.
        let first = try provider.configuration(for: identity).websiteDataStore
        let second = try provider.configuration(for: identity).websiteDataStore
        #expect(first === second)
    }

    @Test("Each identity gets its own persistent store, not the shared default")
    func containersDoNotUseTheDefaultStore() throws {
        let provider = IdentitySessionProvider()
        let identity = Identity(name: "Isolated", color: .amber)
        defer { Task { await provider.destroySession(for: identity) } }

        let store = try provider.configuration(for: identity).websiteDataStore
        #expect(store.isPersistent)
        // Falling back to the default store would silently pool every identity's cookies
        // into one jar while still looking correct in the interface.
        #expect(store !== WKWebsiteDataStore.default())
    }

    @Test("A identity whose proxy is unusable yields no session at all")
    func brokenProxyRefusesToBuildASession() throws {
        let provider = IdentitySessionProvider()
        // A port of zero cannot form an endpoint. The identity must refuse rather than
        // quietly build a direct session — that failure would put the investigator's own
        // address on a subject's server without any visible sign.
        let broken = Identity(
            name: "Broken",
            color: .red,
            proxy: ProxySpec(kind: .socks5, host: "127.0.0.1", port: 0)
        )
        #expect(throws: IdentitySessionProvider.SessionError.self) {
            _ = try provider.configuration(for: broken)
        }
    }

    @Test("A proxy needing a password it does not have yields no session")
    func missingCredentialRefusesToBuildASession() throws {
        let provider = IdentitySessionProvider()
        let identity = Identity(
            name: "NeedsPassword",
            color: .violet,
            proxy: ProxySpec(kind: .http, host: "proxy.example", port: 8080, username: "someone")
        )
        #expect(throws: IdentitySessionProvider.SessionError.self) {
            _ = try provider.configuration(for: identity)
        }
    }
}
