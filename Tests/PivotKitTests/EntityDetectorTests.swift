// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import Testing

@testable import PivotKit

/// Precision matters more than recall here. An investigator offered "look up this domain" on
/// something that is not a domain stops reading the menu, and a menu nobody reads is worse
/// than no menu at all.
@Suite("Entity detection")
struct EntityDetectorTests {

    private func kinds(_ text: String) -> [Entity.Kind] {
        EntityDetector.classify(text).map(\.kind)
    }

    // MARK: Recognised

    @Test("Addresses are recognised", arguments: [
        ("8.8.8.8", Entity.Kind.ipv4),
        ("192.168.1.1", .ipv4),
        ("255.255.255.255", .ipv4),
        ("2001:0db8:85a3:0000:0000:8a2e:0370:7334", .ipv6),
        ("00:1B:44:11:3A:B7", .macAddress),
    ])
    func addressesAreRecognised(_ text: String, _ expected: Entity.Kind) {
        #expect(kinds(text).first == expected, "\(text) read as \(kinds(text))")
    }

    @Test("Identifiers are recognised", arguments: [
        ("CVE-2026-12345", Entity.Kind.cve),
        ("AS15169", .asn),
        ("d41d8cd98f00b204e9800998ecf8427e", .md5),
        ("da39a3ee5e6b4b0d3255bfef95601890afd80709", .sha1),
        ("e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", .sha256),
    ])
    func identifiersAreRecognised(_ text: String, _ expected: Entity.Kind) {
        #expect(kinds(text).first == expected, "\(text) read as \(kinds(text))")
    }

    @Test("Crypto addresses are recognised", arguments: [
        ("1A1zP1eP5QGefi2DMPTfTL5SLmv7DivfNa", Entity.Kind.bitcoinAddress),
        ("bc1qar0srrr7xfkvy5l643lydnw9re59gtzzwf5mdq", .bitcoinAddress),
        ("0x742d35Cc6634C0532925a3b844Bc454e4438f44e", .ethereumAddress),
    ])
    func cryptoAddressesAreRecognised(_ text: String, _ expected: Entity.Kind) {
        #expect(kinds(text).contains(expected), "\(text) read as \(kinds(text))")
    }

    @Test("Web identifiers are recognised")
    func webIdentifiersAreRecognised() {
        #expect(kinds("investigator@example.com").first == .email)
        #expect(kinds("https://example.com/path?q=1").first == .url)
        #expect(kinds("sub.example.co.uk").first == .domain)
        #expect(kinds("@handle_name").contains(.username))
    }

    // MARK: Ambiguity resolved by specificity, not by luck

    @Test("An email is an email, not a domain")
    func emailBeatsDomain() {
        // Both patterns match; the order they are declared in must not decide the answer.
        let result = kinds("investigator@example.com")
        #expect(result.first == .email)
    }

    @Test("An address is an address, not a domain")
    func addressBeatsDomain() {
        #expect(kinds("8.8.8.8").first == .ipv4)
    }

    @Test("A URL is a URL, not just its host")
    func urlBeatsDomain() {
        #expect(kinds("https://example.com").first == .url)
    }

    // MARK: Rejected

    @Test("Out-of-range octets are not addresses", arguments: [
        "999.1.1.1", "256.256.256.256", "1.2.3.4.5", "1.2.3",
    ])
    func invalidAddressesAreRejected(_ text: String) {
        #expect(!kinds(text).contains(.ipv4), "\(text) was read as an address")
    }

    @Test("Version numbers are not domains or addresses", arguments: [
        "1.2.3", "10.0.1", "2026.09.08",
    ])
    func versionNumbersAreNotEntities(_ text: String) {
        let result = kinds(text)
        #expect(!result.contains(.domain), "\(text) was read as a domain")
        #expect(!result.contains(.ipv4), "\(text) was read as an address")
    }

    @Test("Ordinary words are not entities", arguments: [
        "hello", "the subject", "Durham", "N/A", "12", "", "   ",
    ])
    func prosaicTextIsNotAnEntity(_ text: String) {
        // Offering a lookup on a word an investigator happened to select is exactly what
        // teaches people to ignore the menu.
        #expect(kinds(text).isEmpty, "\(text) read as \(kinds(text))")
    }

    @Test("Hex of the wrong length is not a hash", arguments: [
        "abc123", String(repeating: "a", count: 31), String(repeating: "a", count: 33),
        String(repeating: "a", count: 63),
    ])
    func wrongLengthHexIsNotAHash(_ text: String) {
        let result = kinds(text)
        #expect(!result.contains(.md5) && !result.contains(.sha1) && !result.contains(.sha256),
                "\(text) read as \(result)")
    }

    @Test("A hash embedded in a longer hex run is not extracted")
    func hashesNeedBoundaries() {
        // Slicing 32 characters out of a 64-character string would invent an MD5 that is not
        // there and send an investigator looking for a file that does not exist.
        let long = String(repeating: "a", count: 96)
        let found = EntityDetector.scan(long)
        #expect(!found.contains { $0.kind == .md5 })
    }

    // MARK: Normalisation

    @Test("Values are normalised for lookup")
    func valuesAreNormalised() {
        #expect(EntityDetector.classify("Investigator@Example.COM").first?.normalised == "investigator@example.com")
        #expect(EntityDetector.classify("CVE-2026-1234").first?.normalised == "CVE-2026-1234")
        #expect(EntityDetector.classify("00-1B-44-11-3A-B7").first?.normalised == "00:1b:44:11:3a:b7")
        #expect(EntityDetector.classify("+1 (555) 123-4567").first?.normalised == "+15551234567")
        #expect(EntityDetector.classify("@Handle").first?.normalised == "Handle")
    }

    // MARK: Sweeping a page

    @Test("A sweep finds entities inside prose")
    func sweepFindsEntitiesInProse() {
        let text = """
        The registrant listed 8.8.8.8 as a nameserver and gave the address
        investigator@example.com. Payment went to 1A1zP1eP5QGefi2DMPTfTL5SLmv7DivfNa
        and the advisory is CVE-2026-12345.
        """
        let found = EntityDetector.scan(text)
        let kinds = Set(found.map(\.kind))

        #expect(kinds.contains(.ipv4))
        #expect(kinds.contains(.email))
        #expect(kinds.contains(.bitcoinAddress))
        #expect(kinds.contains(.cve))
    }

    @Test("A sweep reports a repeated entity once")
    func sweepDeduplicates() {
        let text = "8.8.8.8 appears, then 8.8.8.8 again, and once more 8.8.8.8."
        #expect(EntityDetector.scan(text).filter { $0.kind == .ipv4 }.count == 1)
    }

    @Test("A sweep leaves out the kinds that would drown it in noise")
    func sweepOmitsLooseKinds() {
        // Phone and username patterns match far too much of ordinary prose to be worth
        // sweeping for; they are offered on an explicit selection instead.
        let text = "Call 555-0134 or write to @someone about order 12-3456-7890."
        let kinds = Set(EntityDetector.scan(text).map(\.kind))
        #expect(!kinds.contains(.phone))
        #expect(!kinds.contains(.username))
    }

    @Test("A sweep is bounded")
    func sweepIsBounded() {
        // A page listing tens of thousands of addresses must not produce a menu that long.
        let text = (0..<300).map { "10.0.\($0 / 256).\($0 % 256)" }.joined(separator: " ")
        #expect(EntityDetector.scan(text, limit: 50).count <= 50)
    }
}
