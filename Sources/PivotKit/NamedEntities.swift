// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import NaturalLanguage

/// Pulls people, organisations and places out of a body of text.
///
/// Uses `NLTagger`, which works on every machine regardless of whether Apple Intelligence is
/// enabled. That matters: an investigator should not lose entity extraction because a system
/// setting is off, and the deterministic tagger is a better fit for this job anyway — it
/// reports what it found, and it does not invent.
public enum NamedEntities {

    public struct Mention: Sendable, Equatable, Hashable {
        public enum Kind: String, Sendable, CaseIterable, Comparable {
            case person
            case organisation
            case place

            /// Only used to break a tie deterministically when a name was read two ways an
            /// equal number of times. Not a claim that one reading is likelier.
            public static func < (lhs: Kind, rhs: Kind) -> Bool {
                allCases.firstIndex(of: lhs)! < allCases.firstIndex(of: rhs)!
            }

            public var displayName: String {
                switch self {
                case .person: "People"
                case .organisation: "Organisations"
                case .place: "Places"
                }
            }
        }

        public let kind: Kind
        public let name: String
        /// How many times it appeared. A name mentioned once may be incidental; one mentioned
        /// twenty times is what the page is about.
        public var count: Int
    }

    /// Extracts named entities, most-mentioned first.
    public static func extract(from text: String, limit: Int = 200) -> [Mention] {
        guard !text.isEmpty else { return [] }

        let tagger = NLTagger(tagSchemes: [.nameType])
        tagger.string = text

        var counts: [Mention.Kind: [String: Int]] = [:]
        let options: NLTagger.Options = [.omitPunctuation, .omitWhitespace, .joinNames]

        tagger.enumerateTags(
            in: text.startIndex..<text.endIndex,
            unit: .word,
            scheme: .nameType,
            options: options
        ) { tag, range in
            guard let tag else { return true }
            let kind: Mention.Kind?
            switch tag {
            case .personalName: kind = .person
            case .organizationName: kind = .organisation
            case .placeName: kind = .place
            default: kind = nil
            }
            guard let kind else { return true }

            let name = String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
            // Single characters and stray fragments are noise rather than names.
            guard name.count >= 3 else { return true }
            counts[kind, default: [:]][name, default: 0] += 1
            return true
        }

        // The tagger will classify the same name several ways across a page — "Bellingcat"
        // read as a person in one sentence and a place in another. Showing both makes the
        // panel contradict itself and undermines the entries that are right, so each name is
        // kept once, under whichever reading the tagger reached most often.
        var best: [String: Mention] = [:]
        for (kind, names) in counts {
            for (name, count) in names {
                let candidate = Mention(kind: kind, name: name, count: count)
                guard let existing = best[name] else {
                    best[name] = candidate
                    continue
                }
                if count > existing.count || (count == existing.count && kind < existing.kind) {
                    best[name] = candidate
                }
            }
        }

        return best.values
            .sorted { ($0.count, $1.name) > ($1.count, $0.name) }
            .prefix(limit)
            .map { $0 }
    }

    /// Mentions grouped for display.
    public static func grouped(_ mentions: [Mention]) -> [(kind: Mention.Kind, mentions: [Mention])] {
        Mention.Kind.allCases.compactMap { kind in
            let matching = mentions.filter { $0.kind == kind }
            return matching.isEmpty ? nil : (kind: kind, mentions: matching)
        }
    }
}
