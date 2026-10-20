// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

/// Decides whether a page has meaningfully changed.
///
/// The hard part of monitoring is not fetching the page again — it is that almost every page
/// differs from itself on every load. View counters tick, timestamps re-render as "3 hours
/// ago", carousels rotate, adverts rotate faster. A watch that reports all of that is a watch
/// the investigator turns off within a day, and then it is not watching anything.
///
/// So comparison happens on normalised text, and a change has to clear a floor before it is
/// reported. What is deliberately *not* done is guessing at which parts of a page matter:
/// stripping "the noisy bits" would eventually discard the sentence the case turned on.
/// Everything is compared; the threshold decides what is worth waking someone for.
public enum ChangeDetector {

    public struct Comparison: Sendable, Equatable {
        public let changed: Bool
        /// 0 to 1. How much of the page is common to both readings.
        public let similarity: Double
        public let addedLines: [String]
        public let removedLines: [String]

        public var addedCount: Int { addedLines.count }
        public var removedCount: Int { removedLines.count }

        /// One line for a notification.
        public var summary: String {
            guard changed else { return "No change" }
            var parts: [String] = []
            if addedCount > 0 { parts.append("\(addedCount) line(s) added") }
            if removedCount > 0 { parts.append("\(removedCount) line(s) removed") }
            return parts.isEmpty ? "Content changed" : parts.joined(separator: ", ")
        }
    }

    /// How much change is worth reporting.
    public enum Sensitivity: String, Codable, Sendable, CaseIterable {
        /// Anything at all, including a single changed word.
        case any
        /// The default. Ignores the handful of lines that differ on almost every load.
        case moderate
        /// Only substantial rewrites.
        case substantial

        public var displayName: String {
            switch self {
            case .any: "Any change"
            case .moderate: "Ignore minor churn"
            case .substantial: "Only major changes"
            }
        }

        public var explanation: String {
            switch self {
            case .any:
                "Reports every difference, including counters and timestamps. Noisy on most "
                + "modern pages."
            case .moderate:
                "Ignores a few differing lines, which is what view counts and relative "
                + "timestamps produce. Suits most pages."
            case .substantial:
                "Only reports when a large part of the page has changed. Use for pages that "
                + "churn constantly."
            }
        }

        /// Lines that may differ before a change is reported, on a page long enough for the
        /// allowance to make sense.
        ///
        /// Counts differing *entries*, not edited lines: changing one line removes one and
        /// adds one, so an allowance of four tolerates two edited lines.
        var lineFloor: Int {
            switch self {
            case .any: 0
            case .moderate: 4
            case .substantial: 12
            }
        }

        /// The allowance scaled to the page.
        ///
        /// A fixed floor is wrong in both directions: two changed lines on a six-line record
        /// is the whole record moving, while the same two lines on a two-thousand-line forum
        /// thread is a view counter. Short pages therefore get no allowance at all and are
        /// compared exactly; long pages get the full one.
        func floor(forLineCount count: Int) -> Int {
            min(lineFloor, max(0, count / 10))
        }

        /// Fraction of the page that must be common for it to count as unchanged.
        var similarityFloor: Double {
            switch self {
            case .any: 1.0
            case .moderate: 0.995
            case .substantial: 0.90
            }
        }
    }

    public static func compare(
        previous: String,
        current: String,
        sensitivity: Sensitivity = .moderate
    ) -> Comparison {
        let before = normalise(previous)
        let after = normalise(current)

        if before == after {
            return Comparison(changed: false, similarity: 1, addedLines: [], removedLines: [])
        }

        // Multiset comparison rather than a positional diff: a page whose sections are
        // reordered has not changed in any way an investigator cares about, and treating it
        // as changed is exactly the false alarm that gets monitoring switched off.
        var beforeCounts: [String: Int] = [:]
        for line in before { beforeCounts[line, default: 0] += 1 }
        var afterCounts: [String: Int] = [:]
        for line in after { afterCounts[line, default: 0] += 1 }

        var added: [String] = []
        var removed: [String] = []
        var common = 0

        for (line, count) in afterCounts {
            let previousCount = beforeCounts[line] ?? 0
            common += min(count, previousCount)
            if count > previousCount {
                added.append(contentsOf: Array(repeating: line, count: count - previousCount))
            }
        }
        for (line, count) in beforeCounts {
            let currentCount = afterCounts[line] ?? 0
            if count > currentCount {
                removed.append(contentsOf: Array(repeating: line, count: count - currentCount))
            }
        }

        let total = max(before.count, after.count)
        let similarity = total == 0 ? 1 : Double(common) / Double(total)
        let differing = added.count + removed.count

        let changed = differing > sensitivity.floor(forLineCount: total)
            && similarity < sensitivity.similarityFloor

        return Comparison(
            changed: changed,
            similarity: similarity,
            // Bounded: a page rewritten wholesale should not put ten thousand lines into a
            // notification or a case note.
            addedLines: Array(added.prefix(80)),
            removedLines: Array(removed.prefix(80))
        )
    }

    /// Collapses the differences that are not differences.
    ///
    /// Runs of whitespace become single spaces and blank lines go, because re-rendering the
    /// same content with different wrapping is not a change. Nothing else is removed — in
    /// particular, numbers are left alone. A follower count is noise on one page and the
    /// finding on another, and the tool is not in a position to know which.
    static func normalise(_ text: String) -> [String] {
        text.split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                     .trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}
