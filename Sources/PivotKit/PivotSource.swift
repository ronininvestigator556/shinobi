// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

/// Somewhere an entity can be looked up.
public struct PivotSource: Equatable, Hashable, Sendable, Identifiable {
    public var id: String { name + template }

    /// What a source is for. Used to group the menu, so ten entries read as four short
    /// groups rather than one long list.
    public enum Category: String, Sendable, CaseIterable, Comparable {
        case registration
        case infrastructure
        case reputation
        case archive
        case search

        public var displayName: String {
            switch self {
            case .registration: "Registration"
            case .infrastructure: "Infrastructure"
            case .reputation: "Reputation"
            case .archive: "Archive"
            case .search: "Search"
            }
        }

        var order: Int {
            switch self {
            case .registration: 0
            case .infrastructure: 1
            case .reputation: 2
            case .archive: 3
            case .search: 4
            }
        }

        public static func < (lhs: Category, rhs: Category) -> Bool { lhs.order < rhs.order }
    }

    public let name: String
    /// URL with `{value}` where the entity goes.
    public let template: String
    public let kinds: Set<Entity.Kind>
    public let category: Category
    /// True when the lookup needs an account or a key to be useful.
    public let requiresAccount: Bool

    public init(
        _ name: String,
        _ template: String,
        kinds: Set<Entity.Kind>,
        category: Category,
        requiresAccount: Bool = false
    ) {
        self.name = name
        self.template = template
        self.kinds = kinds
        self.category = category
        self.requiresAccount = requiresAccount
    }

    /// The URL to open for `entity`, or nil if the value cannot be safely placed in one.
    public func url(for entity: Entity) -> URL? {
        // Percent-encoded rather than interpolated raw: an entity comes off a subject's page
        // and is untrusted input, and a value containing a `&` or a `#` would otherwise
        // silently rewrite the query it was meant to be a parameter of.
        guard let encoded = entity.normalised.addingPercentEncoding(
            withAllowedCharacters: .alphanumerics.union(.init(charactersIn: "-._~"))
        ) else { return nil }
        return URL(string: template.replacingOccurrences(of: "{value}", with: encoded))
    }
}

/// The lookups Shinobi offers.
///
/// A deliberately short list of well-known, generally-free sources rather than an exhaustive
/// one. A pivot menu is only useful if it can be read at a glance; the fifty-entry version
/// that appears in community toolboxes is a reference document, not an interface.
///
/// **Every pivot discloses the entity to whoever runs the source.** Looking up a subject's
/// email address tells that service you are interested in that address, and the lookup leaves
/// from the active container, so it carries that identity's egress. That is inherent to
/// pivoting rather than a flaw in it, but it is a reason the list is short and recognisable:
/// an investigator should know who they are talking to.
public enum PivotRegistry {

    public static let sources: [PivotSource] = [
        // Addresses and infrastructure
        PivotSource("Shodan", "https://www.shodan.io/host/{value}", kinds: [.ipv4, .ipv6], category: .infrastructure),
        PivotSource("Censys", "https://search.censys.io/hosts/{value}", kinds: [.ipv4, .ipv6], category: .infrastructure),
        PivotSource("AbuseIPDB", "https://www.abuseipdb.com/check/{value}", kinds: [.ipv4, .ipv6], category: .reputation),
        PivotSource("GreyNoise", "https://viz.greynoise.io/ip/{value}", kinds: [.ipv4], category: .reputation),
        PivotSource("ipinfo", "https://ipinfo.io/{value}", kinds: [.ipv4, .ipv6, .asn], category: .infrastructure),
        PivotSource("BGP.he.net", "https://bgp.he.net/{value}", kinds: [.asn, .ipv4], category: .infrastructure),

        // Domains
        PivotSource("Whois", "https://who.is/whois/{value}", kinds: [.domain], category: .registration),
        PivotSource("crt.sh", "https://crt.sh/?q={value}", kinds: [.domain], category: .registration),
        PivotSource("DNSdumpster", "https://dnsdumpster.com/?q={value}", kinds: [.domain], category: .infrastructure),
        PivotSource("SecurityTrails", "https://securitytrails.com/domain/{value}/dns",
                    kinds: [.domain], category: .infrastructure, requiresAccount: true),
        PivotSource("BuiltWith", "https://builtwith.com/{value}", kinds: [.domain], category: .infrastructure),

        // Reputation, shared across several kinds
        PivotSource("VirusTotal", "https://www.virustotal.com/gui/search/{value}",
                    kinds: [.ipv4, .ipv6, .domain, .url, .md5, .sha1, .sha256], category: .reputation),
        PivotSource("urlscan.io", "https://urlscan.io/search/#{value}",
                    kinds: [.domain, .url, .ipv4], category: .reputation),

        // Archives
        PivotSource("Wayback Machine", "https://web.archive.org/web/*/{value}",
                    kinds: [.domain, .url], category: .archive),
        PivotSource("archive.today", "https://archive.ph/newest/{value}", kinds: [.domain, .url], category: .archive),

        // People and accounts
        PivotSource("Have I Been Pwned", "https://haveibeenpwned.com/account/{value}",
                    kinds: [.email], category: .reputation),
        PivotSource("EmailRep", "https://emailrep.io/{value}", kinds: [.email], category: .reputation),
        PivotSource("DuckDuckGo", "https://duckduckgo.com/?q=%22{value}%22",
                    kinds: [.email, .username, .phone, .domain], category: .search),

        // Chains
        PivotSource("Blockchair", "https://blockchair.com/search?q={value}",
                    kinds: [.bitcoinAddress, .ethereumAddress], category: .infrastructure),
        PivotSource("mempool.space", "https://mempool.space/address/{value}",
                    kinds: [.bitcoinAddress], category: .infrastructure),
        PivotSource("Etherscan", "https://etherscan.io/address/{value}",
                    kinds: [.ethereumAddress], category: .infrastructure),

        // Vulnerabilities
        PivotSource("NVD", "https://nvd.nist.gov/vuln/detail/{value}", kinds: [.cve], category: .registration),
        PivotSource("MITRE", "https://cve.mitre.org/cgi-bin/cvename.cgi?name={value}", kinds: [.cve], category: .registration),

        // Hardware
        PivotSource("MAC vendor", "https://maclookup.app/search/result?mac={value}",
                    kinds: [.macAddress], category: .registration),
    ]

    public static func sources(for kind: Entity.Kind) -> [PivotSource] {
        sources.filter { $0.kinds.contains(kind) }
    }

    /// Sources for a kind, grouped and ordered for a menu.
    public static func grouped(for kind: Entity.Kind) -> [(category: PivotSource.Category, sources: [PivotSource])] {
        Dictionary(grouping: sources(for: kind), by: \.category)
            .map { (category: $0.key, sources: $0.value.sorted { $0.name < $1.name }) }
            .sorted { $0.category < $1.category }
    }
}
