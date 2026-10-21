// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

/// Converts Adblock Plus filter syntax into WebKit content-blocking rules.
///
/// EasyList and EasyPrivacy are written in ABP syntax, which is considerably more expressive
/// than WebKit's rule format. This translates the subset that maps cleanly and *skips* the
/// rest rather than approximating it: a rule that blocks more than it should is worse here
/// than a rule that is missing, because an investigator whose page silently renders wrong is
/// looking at an inaccurate picture of what an ordinary visitor would have seen.
///
/// Deliberately not supported, and skipped rather than guessed at:
/// `$csp=`, `$redirect=`, `$removeparam=`, `$replace=`, `$popup`, `$websocket`, `$ping`,
/// snippet and scriptlet injections, and free-form `/regex/` filters. Extended CSS selectors
/// (`:has-text`, `:-abp-has`) are skipped too — WebKit's selector engine does not implement
/// them, and a malformed selector poisons the whole compiled list.
public enum AdblockFilterConverter {

    public struct Result: Sendable {
        public var rules: [ContentRule]
        public var converted: Int
        public var skipped: Int
    }

    /// ABP option names that map onto WebKit resource types.
    private static let resourceTypes: [String: String] = [
        "script": "script",
        "image": "image",
        "stylesheet": "style-sheet",
        "css": "style-sheet",
        "font": "font",
        "media": "media",
        "xmlhttprequest": "raw",
        "other": "raw",
        "subdocument": "document",
        "document": "document",
    ]

    /// Options that are meaningful in ABP but have no WebKit equivalent. A rule carrying one
    /// is skipped whole.
    private static let unsupportedOptions: Set<String> = [
        "csp", "redirect", "redirect-rule", "removeparam", "replace", "popup", "popunder",
        "websocket", "ping", "webrtc", "generichide", "genericblock", "elemhide", "inline-script",
        "inline-font", "empty", "mp4", "cname", "denyallow", "method", "header", "permissions",
    ]

    /// The largest rule count WebKit will compile.
    ///
    /// Measured, not documented: compiling the combined EasyList and EasyPrivacy succeeds at
    /// 70,000 rules and fails at 75,000 with `WKErrorDomain` error 6, which carries no
    /// detail. 65,000 leaves headroom, because the community lists grow over time and a
    /// budget that only just fits today would start failing silently on some future update.
    public static let webKitRuleCeiling = 65_000

    /// Converts several lists under one shared budget.
    ///
    /// Necessary because the budget is smaller than the lists. Converting a naive
    /// concatenation lets whichever list comes first consume the entire allowance — with
    /// EasyList first, that left EasyPrivacy contributing almost nothing, quietly turning
    /// "ads and trackers" into "ads". Each list therefore gets a guaranteed share, and any
    /// share a smaller list does not use is handed to the others.
    public static func convert(
        sources: [(name: String, text: String)],
        totalLimit: Int = webKitRuleCeiling
    ) -> Result {
        guard !sources.isEmpty else { return Result(rules: [], converted: 0, skipped: 0) }

        let share = totalLimit / sources.count
        var results: [(name: String, result: Result)] = []
        var spare = 0

        // First pass at an equal share, collecting whatever the smaller lists leave behind.
        for source in sources {
            let result = convert(source.text, limit: share)
            spare += max(0, share - result.converted)
            results.append((source.name, result))
        }

        // Second pass: re-run the lists that were truncated, with the leftover added.
        if spare > 0 {
            for index in results.indices where results[index].result.converted >= share {
                let extra = spare
                spare = 0
                let source = sources[index]
                results[index].result = convert(source.text, limit: share + extra)
                break
            }
        }

        var rules: [ContentRule] = []
        var seen = Set<String>()
        var skipped = 0

        for entry in results {
            skipped += entry.result.skipped
            for rule in entry.result.rules where seen.insert(dedupeKey(rule)).inserted {
                rules.append(rule)
            }
        }

        return Result(rules: rules, converted: rules.count, skipped: skipped)
    }

    public static func convert(_ text: String, limit: Int = webKitRuleCeiling) -> Result {
        var rules: [ContentRule] = []
        var skipped = 0
        var seen = Set<String>()

        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: true) {
            if rules.count >= limit { break }

            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("!") || line.hasPrefix("[") { continue }

            guard let rule = convertLine(line) else {
                skipped += 1
                continue
            }

            // Identical triggers appear repeatedly across combined lists, and WebKit counts
            // every duplicate against the compiled-size limit.
            guard seen.insert(dedupeKey(rule)).inserted else { continue }

            rules.append(rule)
        }

        return Result(rules: rules, converted: rules.count, skipped: skipped)
    }

    private static func dedupeKey(_ rule: ContentRule) -> String {
        "\(rule.trigger.urlFilter)|\(rule.action.type)|\(rule.action.selector ?? "")"
            + "|\(rule.trigger.ifDomain ?? [])|\(rule.trigger.unlessDomain ?? [])"
            + "|\(rule.trigger.resourceType ?? [])|\(rule.trigger.loadType ?? [])"
    }

    // MARK: One line

    static func convertLine(_ line: String) -> ContentRule? {
        if let separator = elementHidingSeparator(in: line) {
            return convertElementHiding(line, separator: separator)
        }
        return convertBlocking(line)
    }

    /// Finds `##` (hide) or `#@#` (exception), which mark element-hiding rules.
    private static func elementHidingSeparator(in line: String) -> Range<String.Index>? {
        // `#@#` must be checked first; it contains no `##`, but ordering keeps intent clear.
        if let range = line.range(of: "#@#") { return range }
        if let range = line.range(of: "##") { return range }
        return nil
    }

    private static func convertElementHiding(_ line: String, separator: Range<String.Index>) -> ContentRule? {
        // Exceptions to element hiding have no WebKit equivalent — there is no way to undo a
        // css-display-none for a narrower scope — so they are skipped.
        guard line[separator] == "##" else { return nil }

        let selector = String(line[separator.upperBound...]).trimmingCharacters(in: .whitespaces)
        guard !selector.isEmpty, isPlainCSSSelector(selector) else { return nil }

        let domainText = String(line[line.startIndex..<separator.lowerBound])
        var ifDomain: [String]?
        var unlessDomain: [String]?

        if !domainText.isEmpty {
            var included: [String] = []
            var excluded: [String] = []
            for entry in domainText.split(separator: ",") {
                let name = entry.trimmingCharacters(in: .whitespaces)
                if name.hasPrefix("~") {
                    excluded.append("*" + name.dropFirst())
                } else if !name.isEmpty {
                    included.append("*" + name)
                }
            }
            ifDomain = included.isEmpty ? nil : included
            unlessDomain = excluded.isEmpty ? nil : excluded
        }

        return ContentRule(
            trigger: .init(
                urlFilter: ".*",
                ifDomain: ifDomain,
                unlessDomain: unlessDomain
            ),
            action: .init(type: "css-display-none", selector: selector)
        )
    }

    /// Rejects extended selectors WebKit cannot parse. One bad selector fails the entire
    /// compiled list, so this errs toward dropping.
    private static func isPlainCSSSelector(_ selector: String) -> Bool {
        let extended = [":has-text(", ":-abp-", ":contains(", ":matches-css", ":xpath(", ":upward(",
                        ":nth-ancestor(", ":watch-attr(", ":remove(", ":style("]
        if extended.contains(where: selector.contains) { return false }
        // `:has()` is supported by modern WebKit, but ABP's variants above are not.
        return !selector.contains("{") && !selector.contains("}")
    }

    private static func convertBlocking(_ line: String) -> ContentRule? {
        var body = line
        var isException = false

        if body.hasPrefix("@@") {
            isException = true
            body = String(body.dropFirst(2))
        }

        // Free-form regex filters are passed through by neither syntax compatibly.
        if body.hasPrefix("/") && body.contains("/$") == false && body.hasSuffix("/") { return nil }

        var options: [String] = []
        if let optionIndex = body.lastIndex(of: "$") {
            let optionText = String(body[body.index(after: optionIndex)...])
            // A `$` inside a URL pattern is not an option marker.
            if !optionText.contains("/") {
                options = optionText.split(separator: ",").map(String.init)
                body = String(body[body.startIndex..<optionIndex])
            }
        }

        guard !body.isEmpty else { return nil }
        guard var trigger = makeTrigger(pattern: body) else { return nil }
        guard applyOptions(options, to: &trigger) else { return nil }

        return ContentRule(
            trigger: trigger,
            action: .init(type: isException ? "ignore-previous-rules" : "block", selector: nil)
        )
    }

    // MARK: Pattern

    static func makeTrigger(pattern: String) -> ContentRule.Trigger? {
        var pattern = pattern
        var regex = ""

        if pattern.hasPrefix("||") {
            pattern = String(pattern.dropFirst(2))
            // Match the host and any subdomain of it, but not a domain that merely ends with
            // the same characters: `([^/]*\.)?` requires a dot boundary.
            regex += "^https?://([^/]*\\.)?"
        } else if pattern.hasPrefix("|") {
            pattern = String(pattern.dropFirst())
            regex += "^"
        }

        var anchorEnd = false
        if pattern.hasSuffix("|") {
            pattern = String(pattern.dropLast())
            anchorEnd = true
        }

        // A trailing separator adds nothing once the pattern is a prefix match.
        if pattern.hasSuffix("^") { pattern = String(pattern.dropLast()) }

        guard !pattern.isEmpty else { return nil }

        for character in pattern {
            switch character {
            case "*":
                regex += ".*"
            case "^":
                // ABP's separator: anything that is not part of a name.
                regex += "[^a-zA-Z0-9_.%-]"
            case ".", "+", "?", "(", ")", "[", "]", "{", "}", "|", "$", "\\", "/":
                regex += "\\" + String(character)
            default:
                regex += String(character)
            }
        }

        if anchorEnd { regex += "$" }
        guard regex.count <= 1_000 else { return nil }

        return ContentRule.Trigger(urlFilter: regex)
    }

    // MARK: Options

    /// Returns false when the rule carries an option WebKit cannot express, meaning the
    /// whole rule must be dropped.
    static func applyOptions(_ options: [String], to trigger: inout ContentRule.Trigger) -> Bool {
        var resources: [String] = []
        var included: [String] = []
        var excluded: [String] = []

        for option in options {
            let negated = option.hasPrefix("~")
            let name = negated ? String(option.dropFirst()) : option

            if name.hasPrefix("domain=") {
                for entry in name.dropFirst("domain=".count).split(separator: "|") {
                    let domain = entry.trimmingCharacters(in: .whitespaces)
                    if domain.hasPrefix("~") {
                        excluded.append("*" + domain.dropFirst())
                    } else if !domain.isEmpty {
                        included.append("*" + domain)
                    }
                }
                continue
            }

            switch name {
            case "third-party":
                trigger.loadType = [negated ? "first-party" : "third-party"]
            case "match-case":
                trigger.urlFilterIsCaseSensitive = true
            case "all":
                continue
            default:
                if let resource = resourceTypes[name] {
                    // A negated resource type cannot be expressed; WebKit has no "everything
                    // except" for resource-type.
                    if negated { return false }
                    resources.append(resource)
                } else if unsupportedOptions.contains(name.split(separator: "=").first.map(String.init) ?? name) {
                    return false
                } else {
                    return false   // unknown option: drop rather than mis-apply
                }
            }
        }

        if !resources.isEmpty { trigger.resourceType = Array(Set(resources)).sorted() }
        if !included.isEmpty { trigger.ifDomain = included }
        if !excluded.isEmpty { trigger.unlessDomain = excluded }
        return true
    }
}
