// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

/// Turns whatever the investigator typed into a URL.
///
/// The bias here is deliberately toward *navigating* rather than *searching*. In OSINT work
/// the address bar receives a lot of bare hosts, IP addresses and onion addresses pasted out
/// of logs and documents, and silently turning `192.168.1.1` or `example.co.uk` into a search
/// query leaks the subject of the investigation to a search engine. When the input is
/// plausibly an address, Shinobi navigates.
public enum URLResolver {

    public static func resolve(_ raw: String) -> URL? {
        let input = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { return nil }

        // Anything with an explicit scheme is taken at its word.
        if hasExplicitScheme(input), let url = URL(string: input) {
            return url
        }

        if looksLikeAddress(input) {
            return URL(string: "https://" + input)
        }

        return searchURL(for: input)
    }

    /// Schemes that legitimately appear without `//`. Everything else must show `://`
    /// before Shinobi will believe it is a scheme.
    private static let schemesWithoutAuthority: Set<String> = [
        "about", "mailto", "data", "tel", "sms", "magnet",
    ]

    /// Whether the input genuinely carries a URL scheme.
    ///
    /// `URL(string:)` cannot be trusted for this on its own. A scheme may contain dots, so
    /// it parses `example.com:8443` as the scheme `example.com`, and `site:example.com bar`
    /// as the scheme `site` — sending a host straight past the address check in the first
    /// case, and a search operator in the second.
    private static func hasExplicitScheme(_ input: String) -> Bool {
        guard let colon = input.firstIndex(of: ":") else { return false }

        let scheme = input[input.startIndex..<colon].lowercased()
        guard let first = scheme.first, first.isLetter else { return false }
        guard scheme.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "+" || $0 == "-" || $0 == "." })
        else { return false }

        // A hierarchical URL must show its authority marker.
        if input[colon...].hasPrefix("://") { return true }

        return schemesWithoutAuthority.contains(scheme)
    }

    /// Whether the input should be treated as a host rather than a search query.
    private static func looksLikeAddress(_ input: String) -> Bool {
        // A space means prose. Nothing else needs checking.
        if input.contains(" ") { return false }

        // Split off any path, query or fragment; only the authority decides this.
        let authority = input.prefix { $0 != "/" && $0 != "?" && $0 != "#" }
        guard !authority.isEmpty else { return false }

        // Strip a port if present.
        let host = authority.split(separator: ":", maxSplits: 1).first.map(String.init) ?? String(authority)
        guard !host.isEmpty else { return false }

        if host == "localhost" { return true }
        if isIPv4(host) { return true }
        if host.hasSuffix(".onion") { return true }

        // Otherwise require a dot and a plausible TLD. This is intentionally loose: it does
        // not validate against the public suffix list, because investigators routinely visit
        // hosts on TLDs that a bundled list would be stale on.
        guard let lastDot = host.lastIndex(of: "."), lastDot != host.startIndex else { return false }
        let tld = host[host.index(after: lastDot)...]
        guard tld.count >= 2, tld.allSatisfy({ $0.isLetter }) else { return false }

        return true
    }

    private static func isIPv4(_ host: String) -> Bool {
        let parts = host.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return false }
        return parts.allSatisfy { part in
            guard !part.isEmpty, part.count <= 3, part.allSatisfy(\.isNumber),
                  let value = Int(part) else { return false }
            return value <= 255
        }
    }

    private static func searchURL(for query: String) -> URL? {
        var components = URLComponents(string: "https://duckduckgo.com/")
        components?.queryItems = [URLQueryItem(name: "q", value: query)]
        return components?.url
    }
}
