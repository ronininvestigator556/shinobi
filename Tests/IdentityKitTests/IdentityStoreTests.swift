// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import Testing

@testable import IdentityKit
@testable import ShinobiKit

@Suite("Identity store")
struct IdentityStoreTests {

    /// Each test gets its own file, so they neither collide nor touch the real identity
    /// list in Application Support.
    private func makeTemporaryURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("shinobi-tests-\(UUID().uuidString)")
            .appendingPathExtension("json")
    }

    @Test("A fresh store always contains Personal")
    func personalAlwaysExists() throws {
        let store = IdentityStore(fileURL: makeTemporaryURL())
        // Every tab needs a identity to live in. A store that can be empty would make
        // "no identity at all" a reachable state.
        #expect(store.all.contains { $0.isPersonal })
    }

    @Test("Identities survive a reload")
    func containersPersist() throws {
        let url = makeTemporaryURL()
        let puppet = Identity(name: "Durham puppet", color: .violet)

        let first = IdentityStore(fileURL: url)
        try first.add(puppet)

        let second = IdentityStore(fileURL: url)
        let reloaded = try #require(second.identity(withID: puppet.id))
        #expect(reloaded.name == "Durham puppet")
        #expect(reloaded.color == .violet)
    }

    @Test("A identity's id is stable across a reload")
    func identifierIsStable() throws {
        let url = makeTemporaryURL()
        let puppet = Identity(name: "Puppet", color: .cyan)

        try IdentityStore(fileURL: url).add(puppet)
        let reloaded = try #require(IdentityStore(fileURL: url).identity(withID: puppet.id))

        // The id names the on-disk WKWebsiteDataStore directory. If it changed between
        // launches the persona would be silently logged out of everything it had a session
        // with, and the old directory would linger unreferenced.
        #expect(reloaded.id == puppet.id)
    }

    @Test("Personal cannot be deleted")
    func personalIsUndeletable() throws {
        let store = IdentityStore(fileURL: makeTemporaryURL())
        #expect(throws: IdentityStore.StoreError.self) {
            try store.remove(id: Identity.personal.id)
        }
        #expect(store.all.contains { $0.isPersonal })
    }

    @Test("Removing a identity forgets it")
    func removeWorks() throws {
        let store = IdentityStore(fileURL: makeTemporaryURL())
        let puppet = Identity(name: "Temporary", color: .red)
        try store.add(puppet)
        try store.remove(id: puppet.id)
        #expect(store.identity(withID: puppet.id) == nil)
    }

    @Test("Updating a identity rewrites it in place")
    func updateWorks() throws {
        let url = makeTemporaryURL()
        let store = IdentityStore(fileURL: url)
        var puppet = Identity(name: "Before", color: .blue)
        try store.add(puppet)

        puppet.name = "After"
        puppet.proxy = ProxySpec(kind: .socks5, host: "127.0.0.1", port: 9050)
        try store.update(puppet)

        let reloaded = try #require(IdentityStore(fileURL: url).identity(withID: puppet.id))
        #expect(reloaded.name == "After")
        #expect(reloaded.proxy?.port == 9050)
        #expect(IdentityStore(fileURL: url).all.filter { $0.id == puppet.id }.count == 1)
    }

    @Test("A corrupt file does not lose the Personal identity")
    func corruptFileRecovers() throws {
        let url = makeTemporaryURL()
        try Data("{ not json".utf8).write(to: url)

        // Truncated or hand-mangled JSON must degrade to a usable app, not a crash or an
        // empty identity list.
        let store = IdentityStore(fileURL: url)
        #expect(store.all.contains { $0.isPersonal })
    }
}

@Suite("Identity encoding")
struct IdentityCodingTests {

    @Test("A identity round-trips through JSON")
    func roundTrips() throws {
        let original = Identity(
            name: "Berlin persona",
            color: .amber,
            proxy: ProxySpec(kind: .http, host: "proxy.example", port: 8080, username: "user"),
            userAgent: .custom("Mozilla/5.0 (Windows NT 10.0; Win64; x64)"),
            timezone: "Europe/Berlin",
            blocking: .strict
        )

        let data = try JSONEncoder.shinobi().encode(original)
        let decoded = try JSONDecoder.shinobi().decode(Identity.self, from: data)
        #expect(decoded == original)
    }

    @Test("A timestamp survives its own round trip exactly")
    func timestampsAreLossless() throws {
        let identity = Identity(name: "x", color: .blue, createdAt: Date())
        let data = try JSONEncoder.shinobi().encode(identity)
        let decoded = try JSONDecoder.shinobi().decode(Identity.self, from: data)
        #expect(decoded.createdAt == identity.createdAt)
    }

    @Test("Timestamp round-tripping is exact across the calendar, not just for today")
    func timestampRoundTripIsExactEverywhere() throws {
        // This is the regression guard for a measured finding, not a hypothetical. Encoding
        // a Date with *fractional* seconds and decoding it yields a different Date about
        // half the time, because the Double behind Date cannot be recovered from a
        // millisecond string. Whole seconds are exact. A future change to the timestamp
        // format that reintroduces sub-second precision will fail here rather than quietly
        // making saved timestamps unstable.
        var generator = SystemRandomNumberGenerator()
        for _ in 0..<2000 {
            let raw = Date(timeIntervalSinceReferenceDate: .random(in: 0...900_000_000, using: &generator))
            let normalised = raw.roundedToPersistedPrecision()

            let text = normalised.formatted(Date.ISO8601FormatStyle.shinobiTimestamp)
            let decoded = try Date(text, strategy: Date.ISO8601FormatStyle.shinobiTimestamp)

            #expect(decoded == normalised)
            #expect(decoded.roundedToPersistedPrecision() == decoded)   // idempotent
        }
    }

    @Test("Colours are stored by name, not position")
    func colourIsStoredByName() throws {
        let identity = Identity(name: "x", color: .violet)
        let json = try JSONEncoder.shinobi().encode(identity)
        let text = try #require(String(data: json, encoding: .utf8))

        // Persisting an index into the palette array would silently recolour every saved
        // identity the moment an entry was inserted, and a identity that changes colour
        // between launches defeats the whole point of the signal.
        #expect(text.contains("\"violet\""))
    }

    @Test("The proxy password is never encoded")
    func passwordIsNotSerialised() throws {
        let identity = Identity(
            name: "x",
            color: .blue,
            proxy: ProxySpec(kind: .socks5, host: "h", port: 1080, username: "user")
        )
        let text = try #require(String(data: try JSONEncoder.shinobi().encode(identity), encoding: .utf8))

        // Credentials to the investigator's egress infrastructure belong in the Keychain.
        // This asserts the model has no field that could carry one into the JSON file.
        #expect(!text.lowercased().contains("password"))
        #expect(!text.lowercased().contains("secret"))
    }
}

@Suite("Proxy configuration")
struct ProxySpecTests {

    @Test("A well-formed spec produces a configuration", arguments: [
        ProxySpec(kind: .socks5, host: "127.0.0.1", port: 9050),
        ProxySpec(kind: .http, host: "proxy.example.com", port: 8080),
    ])
    func validSpecsBuild(_ spec: ProxySpec) {
        #expect(spec.makeProxyConfiguration(password: nil) != nil)
    }

    @Test("A malformed spec produces nothing", arguments: [
        ProxySpec(kind: .socks5, host: "", port: 9050),
        ProxySpec(kind: .http, host: "   ", port: 8080),
        ProxySpec(kind: .http, host: "proxy.example.com", port: 0),
    ])
    func invalidSpecsFail(_ spec: ProxySpec) {
        // The caller treats nil as "load nothing". Silently returning a direct connection
        // here would put the investigator's own address on a subject's server.
        #expect(spec.makeProxyConfiguration(password: nil) == nil)
    }

    @Test("A username marks the spec as needing a password")
    func credentialRequirementIsDetected() {
        #expect(ProxySpec(kind: .http, host: "h", port: 1, username: "u").requiresPassword)
        #expect(!ProxySpec(kind: .http, host: "h", port: 1).requiresPassword)
        #expect(!ProxySpec(kind: .http, host: "h", port: 1, username: "").requiresPassword)
    }
}

@Suite("WebKit session identifiers")
struct WebSessionIdentifierTests {

    @Test("The two reserved identifiers are rejected", arguments: [
        "00000000-0000-0000-0000-000000000000",
        "00000000-0000-0000-0000-000000000001",
    ])
    func reservedIdentifiersAreRejected(_ raw: String) throws {
        // Established by calling WKWebsiteDataStore(forIdentifier:) directly: these two, and
        // only these two, raise NSInvalidArgumentException. WebKit uses them as its own
        // hash-table sentinels. The exception is an Objective-C one, so it cannot be caught
        // in Swift — validating up front is the only way to fail safely.
        let id = try #require(UUID(uuidString: raw))
        #expect(WebSessionIdentifier.isReserved(id))
        #expect(throws: WebSessionIdentifier.ValidationError.self) {
            try WebSessionIdentifier.validate(id)
        }
    }

    @Test("Identifiers that merely look unusual are accepted", arguments: [
        "00000000-0000-0000-0000-000000000002",   // one past the deleted sentinel
        "00000000-0000-0000-1000-000000000000",   // zero version field
        "00000000-0000-4000-8000-000000000001",   // mostly zeros, valid v4 shape
        "11111111-1111-1111-1111-111111111111",
        "ffffffff-ffff-ffff-ffff-ffffffffffff",
    ])
    func unusualButValidIdentifiersAreAccepted(_ raw: String) throws {
        // Guards against over-tightening the rule. The exception message points at the
        // identifier being "invalid", which reads like a version-field requirement; it is
        // not, and rejecting these would needlessly forbid usable ids.
        let id = try #require(UUID(uuidString: raw))
        #expect(!WebSessionIdentifier.isReserved(id))
        #expect(throws: Never.self) { try WebSessionIdentifier.validate(id) }
    }

    @Test("The Personal identity uses a usable identifier")
    func personalIdentifierIsUsable() {
        // This is the regression guard for the actual bug: Personal shipped with the id
        // 00000000-0000-0000-0000-000000000001 because it read nicely, which is exactly the
        // reserved "deleted" sentinel. Every tab creation threw an uncatchable exception.
        #expect(!WebSessionIdentifier.isReserved(Identity.personal.id))
    }

    @Test("Freshly generated identifiers are always usable")
    func generatedIdentifiersAreUsable() {
        for _ in 0..<1000 {
            #expect(!WebSessionIdentifier.isReserved(UUID()))
        }
    }
}
