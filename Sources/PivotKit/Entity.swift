// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

/// Something recognisable in text that an investigator can look up somewhere.
public struct Entity: Equatable, Hashable, Sendable {
    public let kind: Kind
    /// The text as it appeared.
    public let raw: String
    /// The form used when building a lookup URL — lowercased hosts, stripped separators.
    public let normalised: String

    public init(kind: Kind, raw: String, normalised: String? = nil) {
        self.kind = kind
        self.raw = raw
        self.normalised = normalised ?? raw
    }

    public enum Kind: String, Sendable, CaseIterable, Comparable {
        case ipv4
        case ipv6
        case domain
        case url
        case email
        case phone
        case md5
        case sha1
        case sha256
        case bitcoinAddress
        case ethereumAddress
        case cve
        case asn
        case macAddress
        case username

        public var displayName: String {
            switch self {
            case .ipv4: "IPv4 address"
            case .ipv6: "IPv6 address"
            case .domain: "Domain"
            case .url: "URL"
            case .email: "Email address"
            case .phone: "Phone number"
            case .md5: "MD5 hash"
            case .sha1: "SHA-1 hash"
            case .sha256: "SHA-256 hash"
            case .bitcoinAddress: "Bitcoin address"
            case .ethereumAddress: "Ethereum address"
            case .cve: "CVE"
            case .asn: "ASN"
            case .macAddress: "MAC address"
            case .username: "Username"
            }
        }

        /// Ordering used when a fragment matches several kinds: the most specific wins.
        /// `1.2.3.4` is an IPv4 address, not a domain, and `a@b.com` is an email, not a domain.
        var specificity: Int {
            switch self {
            case .cve: 100
            case .email: 95
            case .url: 90
            case .ipv6: 85
            case .ipv4: 80
            case .macAddress: 78
            case .asn: 75
            case .sha256: 70
            case .sha1: 69
            case .md5: 68
            case .ethereumAddress: 65
            case .bitcoinAddress: 60
            case .phone: 40
            case .domain: 30
            case .username: 10
            }
        }

        public static func < (lhs: Kind, rhs: Kind) -> Bool {
            lhs.specificity > rhs.specificity      // most specific sorts first
        }
    }
}
