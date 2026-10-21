// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import Testing

@testable import IdentityKit

@Suite("Adblock filter conversion")
struct AdblockFilterConverterTests {

    // MARK: Domain anchoring

    @Test("A domain anchor matches the domain and its subdomains")
    func domainAnchorMatchesSubdomains() throws {
        let rule = try #require(AdblockFilterConverter.convertLine("||ads.example.com^"))
        let regex = try NSRegularExpression(pattern: rule.trigger.urlFilter)

        for url in ["https://ads.example.com/a.js", "https://x.ads.example.com/a.js", "http://ads.example.com/"] {
            #expect(matches(regex, url), "should match \(url)")
        }
    }

    @Test("A domain anchor does not match a domain that merely ends the same way")
    func domainAnchorDoesNotOvermatch() throws {
        // The classic conversion bug: `example.com` matching `notexample.com`, which would
        // block a site the investigator actually meant to look at.
        let rule = try #require(AdblockFilterConverter.convertLine("||example.com^"))
        let regex = try NSRegularExpression(pattern: rule.trigger.urlFilter)

        #expect(matches(regex, "https://example.com/x"))
        #expect(!matches(regex, "https://notexample.com/x"))
        #expect(!matches(regex, "https://evil-example.com/x"))
    }

    @Test("Wildcards and separators translate")
    func wildcardsTranslate() throws {
        let rule = try #require(AdblockFilterConverter.convertLine("||cdn.example.com/track/*/pixel"))
        let regex = try NSRegularExpression(pattern: rule.trigger.urlFilter)
        #expect(matches(regex, "https://cdn.example.com/track/abc/pixel"))
        #expect(!matches(regex, "https://cdn.example.com/track/pixel-other"))
    }

    @Test("Regex metacharacters in a filter are escaped, not interpreted")
    func metacharactersAreEscaped() throws {
        // `?` and `.` are literal in ABP. Left unescaped they would silently widen the rule.
        let rule = try #require(AdblockFilterConverter.convertLine("||example.com/ad.php?id="))
        let regex = try NSRegularExpression(pattern: rule.trigger.urlFilter)
        #expect(matches(regex, "https://example.com/ad.php?id=1"))
        #expect(!matches(regex, "https://example.com/adXphpYid="))
    }

    // MARK: Actions

    @Test("A plain filter blocks")
    func plainFilterBlocks() throws {
        let rule = try #require(AdblockFilterConverter.convertLine("||tracker.example^"))
        #expect(rule.action.type == "block")
    }

    @Test("An exception filter ignores previous rules")
    func exceptionFilterAllows() throws {
        let rule = try #require(AdblockFilterConverter.convertLine("@@||cdn.example.com^"))
        #expect(rule.action.type == "ignore-previous-rules")
    }

    @Test("An element-hiding filter becomes a display-none rule scoped to its domains")
    func elementHidingConverts() throws {
        let rule = try #require(AdblockFilterConverter.convertLine("example.com,test.org##.ad-banner"))
        #expect(rule.action.type == "css-display-none")
        #expect(rule.action.selector == ".ad-banner")
        #expect(rule.trigger.ifDomain == ["*example.com", "*test.org"])
    }

    @Test("A generic element-hiding filter applies everywhere")
    func genericElementHidingConverts() throws {
        let rule = try #require(AdblockFilterConverter.convertLine("##.sponsored"))
        #expect(rule.action.type == "css-display-none")
        #expect(rule.trigger.ifDomain == nil)
    }

    @Test("Domain exclusions become unless-domain")
    func elementHidingExclusions() throws {
        let rule = try #require(AdblockFilterConverter.convertLine("~safe.com##.ad"))
        #expect(rule.trigger.unlessDomain == ["*safe.com"])
    }

    // MARK: Options

    @Test("Resource types translate")
    func resourceTypesTranslate() throws {
        let rule = try #require(AdblockFilterConverter.convertLine("||example.com^$script,image"))
        #expect(rule.trigger.resourceType == ["image", "script"])
    }

    @Test("Third-party translates in both directions")
    func loadTypeTranslates() throws {
        let third = try #require(AdblockFilterConverter.convertLine("||example.com^$third-party"))
        #expect(third.trigger.loadType == ["third-party"])
        let first = try #require(AdblockFilterConverter.convertLine("||example.com^$~third-party"))
        #expect(first.trigger.loadType == ["first-party"])
    }

    @Test("A domain option becomes if-domain and unless-domain")
    func domainOptionTranslates() throws {
        let rule = try #require(AdblockFilterConverter.convertLine("||ads.example^$domain=news.com|~sport.news.com"))
        #expect(rule.trigger.ifDomain == ["*news.com"])
        #expect(rule.trigger.unlessDomain == ["*sport.news.com"])
    }

    // MARK: What must be dropped

    @Test("Rules with inexpressible options are dropped, not approximated", arguments: [
        "||example.com^$csp=script-src 'none'",
        "||example.com^$redirect=noopjs",
        "||example.com^$removeparam=utm_source",
        "||example.com^$websocket",
        "||example.com^$popup",
        "||example.com^$~script",
    ])
    func inexpressibleOptionsAreDropped(_ line: String) {
        // A rule that blocks more than intended is worse than a missing rule: an exhibit
        // should show what an ordinary visitor would have seen, and a page mangled by an
        // over-broad rule is a misleading record.
        #expect(AdblockFilterConverter.convertLine(line) == nil, "should have dropped: \(line)")
    }

    @Test("Extended CSS selectors are dropped", arguments: [
        "example.com##.ad:has-text(Sponsored)",
        "example.com##.box:-abp-has(.ad)",
        "example.com##div:xpath(//div)",
    ])
    func extendedSelectorsAreDropped(_ line: String) {
        // WebKit cannot parse these, and one bad selector fails the entire compiled list.
        #expect(AdblockFilterConverter.convertLine(line) == nil, "should have dropped: \(line)")
    }

    // MARK: Whole lists

    @Test("Comments and section headers are ignored, and duplicates collapse")
    func listConversionIgnoresNoise() {
        let list = """
        [Adblock Plus 2.0]
        ! Title: Test list
        ! Expires: 1 day

        ||ads.example.com^
        ||ads.example.com^
        ||tracker.example.net^$third-party
        example.com##.ad
        ||example.com^$csp=default-src 'none'
        """
        let result = AdblockFilterConverter.convert(list)

        #expect(result.converted == 3)      // duplicate collapsed
        #expect(result.skipped == 1)        // the csp rule
    }

    @Test("Conversion respects the rule limit")
    func limitIsRespected() {
        let list = (0..<200).map { "||ads\($0).example.com^" }.joined(separator: "\n")
        let result = AdblockFilterConverter.convert(list, limit: 50)
        #expect(result.converted == 50)
    }

    @Test("Every produced url-filter is a regex WebKit can compile")
    func producedFiltersAreValidRegexes() throws {
        let list = """
        ||ads.example.com^
        ||example.com/a.php?id=$script
        |https://example.com/x|
        ||example.com/*/beacon
        ##.sponsored
        @@||cdn.example.com^
        ||a-b_c.example.com^
        """
        for rule in AdblockFilterConverter.convert(list).rules {
            // An invalid pattern would fail the whole list at compile time, taking every
            // other rule down with it.
            #expect(throws: Never.self) {
                _ = try NSRegularExpression(pattern: rule.trigger.urlFilter)
            }
        }
    }

    @Test("Rules encode to the exact JSON keys WebKit expects")
    func encodingUsesWebKitKeys() throws {
        let rule = try #require(AdblockFilterConverter.convertLine("||example.com^$third-party,script"))
        let data = try JSONEncoder().encode([rule])
        let text = try #require(String(data: data, encoding: .utf8))

        for key in ["url-filter", "resource-type", "load-type", "trigger", "action"] {
            #expect(text.contains("\"\(key)\""), "missing key \(key)")
        }
    }

    // MARK: Budgeting across several lists

    @Test("A large first list cannot starve a later one")
    func budgetIsSharedBetweenLists() {
        // The regression guard for a real bug. `standard` concatenated EasyList then
        // EasyPrivacy and converted the result under one limit; EasyList alone exceeded the
        // budget, so EasyPrivacy contributed almost nothing and "ads and trackers" quietly
        // became "ads" — with nothing in the interface saying so.
        let huge = (0..<5_000).map { "||ads\($0).example.com^" }.joined(separator: "\n")
        let small = (0..<50).map { "||tracker\($0).example.net^" }.joined(separator: "\n")

        let result = AdblockFilterConverter.convert(
            sources: [("Huge", huge), ("Small", small)],
            totalLimit: 1_000
        )

        let trackerRules = result.rules.filter { $0.trigger.urlFilter.contains("tracker") }
        #expect(trackerRules.count == 50, "the smaller list was starved")
        #expect(result.converted == 1_000)
    }

    @Test("Budget a smaller list does not use is given to the larger one")
    func unusedBudgetIsReallocated() {
        // Otherwise an equal split would waste half the budget whenever one list is short.
        let huge = (0..<5_000).map { "||ads\($0).example.com^" }.joined(separator: "\n")
        let tiny = "||one.example.net^"

        let result = AdblockFilterConverter.convert(
            sources: [("Huge", huge), ("Tiny", tiny)],
            totalLimit: 1_000
        )
        #expect(result.converted == 1_000)
    }

    @Test("Rules duplicated across lists are counted once")
    func duplicatesAcrossListsCollapse() {
        let result = AdblockFilterConverter.convert(
            sources: [("A", "||ads.example.com^"), ("B", "||ads.example.com^")],
            totalLimit: 100
        )
        #expect(result.converted == 1)
    }

    // MARK: Helper

    private func matches(_ regex: NSRegularExpression, _ url: String) -> Bool {
        regex.firstMatch(in: url, range: NSRange(url.startIndex..., in: url)) != nil
    }
}
