// SPDX-License-Identifier: GPL-3.0-or-later
import CryptoKit
import Foundation
import WebKit

/// Compiles filter lists into `WKContentRuleList`s and caches them.
///
/// Compilation is genuinely expensive — tens of thousands of rules take seconds — so results
/// are kept in WebKit's own on-disk rule-list store and looked up by an identifier derived
/// from the source text. A list that has not changed is never recompiled, and changing the
/// source produces a different identifier automatically.
@MainActor
public final class ContentBlockerCompiler {

    public struct Report: Sendable {
        public let level: BlockingLevel
        public let converted: Int
        public let skipped: Int
        /// True when the budget, not the source lists, decided the rule count.
        public let truncated: Bool
    }

    private let listStore: FilterListStore
    private let ruleListStore: WKContentRuleListStore
    private var compiled: [BlockingLevel: WKContentRuleList] = [:]

    public init(listStore: FilterListStore, ruleListStore: WKContentRuleListStore? = nil) {
        self.listStore = listStore
        self.ruleListStore = ruleListStore ?? .default()
    }

    public func ruleList(for level: BlockingLevel) -> WKContentRuleList? { compiled[level] }

    /// Builds the rule list for a level, reusing WebKit's cache when possible.
    @discardableResult
    public func compile(_ level: BlockingLevel) async throws -> Report? {
        guard level != .off else {
            compiled[level] = nil
            return nil
        }

        let sources = await listStore.sources(for: level)
        guard !sources.isEmpty else { return nil }

        // WebKit reports a compile failure as an opaque error with no detail, so a budget
        // that is slightly too large is indistinguishable from a malformed rule. Rather than
        // lose blocking entirely when the community lists grow past what this version was
        // measured against, step the budget down and try again.
        var lastError: Error?
        for budget in Self.budgetLadder {
            let result = AdblockFilterConverter.convert(sources: sources, totalLimit: budget)
            guard !result.rules.isEmpty else { return nil }

            let json = String(decoding: try JSONEncoder().encode(result.rules), as: UTF8.self)
            let identifier = Self.identifier(for: level, json: json)
            let report = Report(
                level: level,
                converted: result.converted,
                skipped: result.skipped,
                truncated: result.converted >= budget
            )

            if let cached = try? await ruleListStore.contentRuleList(forIdentifier: identifier) {
                compiled[level] = cached
                return report
            }

            do {
                compiled[level] = try await ruleListStore.compileContentRuleList(
                    forIdentifier: identifier,
                    encodedContentRuleList: json
                )
                // Old versions of this level's list are dead weight once the source changes.
                await removeStaleLists(keeping: identifier, for: level)
                return report
            } catch {
                lastError = error
            }
        }

        if let lastError { throw lastError }
        return nil
    }

    /// Budgets tried in order. The first is what the current lists were measured to compile
    /// at; the rest are fallbacks for when they outgrow it.
    private static let budgetLadder = [
        AdblockFilterConverter.webKitRuleCeiling,
        45_000,
        30_000,
    ]

    /// Compiles every level a identity might use.
    @discardableResult
    public func compileAll() async -> [Report] {
        var reports: [Report] = []
        for level in BlockingLevel.allCases where level != .off {
            if let report = try? await compile(level) { reports.append(report) }
        }
        return reports
    }

    private func removeStaleLists(keeping identifier: String, for level: BlockingLevel) async {
        let existing = await withCheckedContinuation { continuation in
            ruleListStore.getAvailableContentRuleListIdentifiers { identifiers in
                continuation.resume(returning: identifiers ?? [])
            }
        }
        for stale in existing where stale.hasPrefix("\(level.rawValue)-") && stale != identifier {
            try? await ruleListStore.removeContentRuleList(forIdentifier: stale)
        }
    }

    /// Identifier derived from the compiled JSON, so a changed source cannot reuse a stale
    /// compiled list.
    private static func identifier(for level: BlockingLevel, json: String) -> String {
        let digest = SHA256.hash(data: Data(json.utf8))
        let hex = digest.compactMap { String(format: "%02x", $0) }.joined().prefix(16)
        return "\(level.rawValue)-\(hex)"
    }
}
