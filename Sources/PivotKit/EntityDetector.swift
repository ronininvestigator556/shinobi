// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

/// Recognises what a piece of selected text is.
///
/// Tuned for precision over recall. A false positive costs more than a miss here: an
/// investigator who is offered "look up this domain" on a fragment that is not a domain learns
/// to stop reading the menu, and a menu nobody reads is worse than no menu. So the patterns
/// are anchored, the ambiguous cases are resolved by specificity rather than by order of
/// evaluation, and anything that cannot be pinned down is simply not offered.
public enum EntityDetector {

    /// Everything `text` is, most specific first.
    ///
    /// A fragment can legitimately be several things — `example.com` is a domain and could be
    /// a URL — so this returns all of them rather than guessing at one.
    public static func classify(_ text: String) -> [Entity] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 2048 else { return [] }

        var found: [Entity] = []
        for matcher in matchers where matcher.matchesWhole(trimmed) {
            found.append(matcher.entity(trimmed))
        }
        return found.sorted { $0.kind < $1.kind }
    }

    /// Everything recognisable *inside* a longer passage, de-duplicated.
    ///
    /// Used for the page-wide sweep rather than for a selection, so it deliberately skips the
    /// loosest kinds: scanning arbitrary prose for usernames or phone numbers produces mostly
    /// noise, and the value of the sweep is that its output is worth reading.
    public static func scan(_ text: String, limit: Int = 500) -> [Entity] {
        var seen = Set<String>()
        var found: [Entity] = []

        for matcher in matchers where matcher.usableInSweep {
            for candidate in matcher.matches(in: text) {
                guard found.count < limit else { return found }
                let entity = matcher.entity(candidate)
                let key = "\(entity.kind.rawValue)|\(entity.normalised)"
                // A page mentioning one address forty times should offer it once.
                guard seen.insert(key).inserted else { continue }
                found.append(entity)
            }
        }
        return found.sorted { $0.kind < $1.kind }
    }

    // MARK: Matchers

    private struct Matcher: Sendable {
        let kind: Entity.Kind
        let pattern: String
        /// Whether the pattern is precise enough to run over arbitrary prose.
        let usableInSweep: Bool
        let validate: (@Sendable (String) -> Bool)?
        let normalise: (@Sendable (String) -> String)?

        init(
            _ kind: Entity.Kind,
            _ pattern: String,
            usableInSweep: Bool = true,
            validate: (@Sendable (String) -> Bool)? = nil,
            normalise: (@Sendable (String) -> String)? = nil
        ) {
            self.kind = kind
            self.pattern = pattern
            self.usableInSweep = usableInSweep
            self.validate = validate
            self.normalise = normalise
        }

        func matchesWhole(_ text: String) -> Bool {
            guard let regex = try? NSRegularExpression(pattern: "^(?:\(pattern))$", options: [.caseInsensitive]),
                  regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
            else { return false }
            return validate?(text) ?? true
        }

        func matches(in text: String) -> [String] {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
            else { return [] }
            return regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
                .compactMap { Range($0.range, in: text).map { String(text[$0]) } }
                .filter { validate?($0) ?? true }
        }

        func entity(_ raw: String) -> Entity {
            Entity(kind: kind, raw: raw, normalised: normalise?(raw) ?? raw)
        }
    }

    /// Word boundaries that also treat the characters common in identifiers as boundaries, so
    /// a hash inside a sentence is found but a hash inside a longer hex run is not.
    private static let boundary = "(?<![A-Za-z0-9])"
    private static let endBoundary = "(?![A-Za-z0-9])"

    private static let matchers: [Matcher] = [
        Matcher(.cve, "CVE-\\d{4}-\\d{4,7}", normalise: { $0.uppercased() }),

        Matcher(.email,
                "[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,63}",
                normalise: { $0.lowercased() }),

        Matcher(.url, "https?://[^\\s\"'<>]+"),

        // Eight groups, or a compressed form containing "::". An earlier pattern accepted any
        // run of colon-separated hex, which made every MAC address look like an IPv6 address —
        // the loose pattern was the bug, not the priority between the two kinds.
        Matcher(.ipv6,
                "(?:[0-9A-Fa-f]{1,4}:){7}[0-9A-Fa-f]{1,4}"
                + "|(?:[0-9A-Fa-f]{1,4}(?::[0-9A-Fa-f]{1,4})*)?::(?:[0-9A-Fa-f]{1,4}(?::[0-9A-Fa-f]{1,4})*)?",
                normalise: { $0.lowercased() }),

        Matcher(.ipv4,
                "\(boundary)(?:\\d{1,3}\\.){3}\\d{1,3}\(endBoundary)",
                validate: { text in
                    // The regex allows 999.999.999.999; the octet range is what makes it an
                    // address rather than four numbers with dots.
                    text.split(separator: ".").allSatisfy {
                        guard let value = Int($0), $0.count <= 3 else { return false }
                        return (0...255).contains(value)
                    }
                }),

        Matcher(.macAddress, "\(boundary)(?:[0-9A-Fa-f]{2}[:-]){5}[0-9A-Fa-f]{2}\(endBoundary)",
                normalise: { $0.lowercased().replacingOccurrences(of: "-", with: ":") }),

        Matcher(.asn, "\(boundary)AS\\d{1,10}\(endBoundary)", normalise: { $0.uppercased() }),

        Matcher(.sha256, "\(boundary)[A-Fa-f0-9]{64}\(endBoundary)", normalise: { $0.lowercased() }),
        Matcher(.sha1, "\(boundary)[A-Fa-f0-9]{40}\(endBoundary)", normalise: { $0.lowercased() }),
        Matcher(.md5, "\(boundary)[A-Fa-f0-9]{32}\(endBoundary)", normalise: { $0.lowercased() }),

        Matcher(.ethereumAddress, "\(boundary)0x[A-Fa-f0-9]{40}\(endBoundary)",
                normalise: { $0.lowercased() }),

        // Legacy base58 and bech32 forms. Base58 excludes 0, O, I and l by design.
        Matcher(.bitcoinAddress,
                "\(boundary)(?:[13][a-km-zA-HJ-NP-Z1-9]{25,34}|bc1[a-z0-9]{25,62})\(endBoundary)"),

        Matcher(.domain,
                "\(boundary)(?:[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?\\.)+[A-Za-z]{2,63}\(endBoundary)",
                usableInSweep: true,
                validate: { text in
                    // A trailing all-numeric label means this is a version string or an
                    // address, not a host.
                    guard let tld = text.split(separator: ".").last else { return false }
                    return tld.allSatisfy(\.isLetter) && text.count <= 253
                },
                normalise: { $0.lowercased() }),

        Matcher(.phone,
                "\\+?[0-9][0-9 ()\\-.]{6,20}[0-9]",
                usableInSweep: false,      // matches far too much in ordinary prose
                validate: { text in
                    let digits = text.filter(\.isNumber)
                    return (7...15).contains(digits.count)
                },
                normalise: { "+" + $0.filter(\.isNumber) }),

        Matcher(.username, "@[A-Za-z0-9_.]{2,30}",
                usableInSweep: false,      // every email in a page would match the tail
                normalise: { String($0.dropFirst()) }),
    ]
}
