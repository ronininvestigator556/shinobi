// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import Testing

@testable import IdentityKit

/// Exercises the converter against the actual community lists, when they have been
/// downloaded on this machine.
///
/// The synthetic tests pin down intent; this one checks the converter survives contact with
/// two megabytes of real-world syntax, including the malformed and exotic entries that
/// accumulate in a list maintained by thousands of people. Skipped when the lists are absent
/// so the suite never depends on the network.
enum DownloadedLists {
    static var easyList: URL {
        FilterListStore.defaultDirectory().appendingPathComponent("easyList.txt")
    }

    static var easyPrivacy: URL {
        FilterListStore.defaultDirectory().appendingPathComponent("easyPrivacy.txt")
    }

    static var arePresent: Bool {
        FileManager.default.fileExists(atPath: easyList.path)
            && FileManager.default.fileExists(atPath: easyPrivacy.path)
    }
}

@Suite("Real filter lists", .enabled(if: DownloadedLists.arePresent))
struct RealFilterListTests {

    @Test("EasyList converts to rules WebKit can compile")
    func easyListConverts() throws {
        let text = try String(contentsOf: DownloadedLists.easyList, encoding: .utf8)
        let result = AdblockFilterConverter.convert(text)

        print("EasyList: \(result.converted) converted, \(result.skipped) skipped")
        #expect(result.converted > 5_000, "suspiciously few rules converted")

        // Every emitted pattern must be a regex WebKit will accept. One bad pattern fails
        // the whole compiled list, so this is all-or-nothing in production.
        for rule in result.rules {
            #expect(throws: Never.self) {
                _ = try NSRegularExpression(pattern: rule.trigger.urlFilter)
            }
        }
    }

    @Test("Both community lists are represented under the shared budget")
    func bothListsSurviveBudgeting() throws {
        let easy = try String(contentsOf: DownloadedLists.easyList, encoding: .utf8)
        let priv = try String(contentsOf: DownloadedLists.easyPrivacy, encoding: .utf8)

        let result = AdblockFilterConverter.convert(
            sources: [("EasyList", easy), ("EasyPrivacy", priv)],
            totalLimit: AdblockFilterConverter.webKitRuleCeiling
        )
        print("Combined: \(result.converted) converted, \(result.skipped) skipped")

        // The specific failure this guards: EasyList exhausting the budget first and leaving
        // tracker blocking effectively switched off while the interface still says
        // "Ads and trackers".
        let probes = [
            "https://www.google-analytics.com/analytics.js",
            "https://connect.facebook.net/en_US/fbevents.js",
        ]
        let blocking = result.rules.filter { $0.action.type == "block" }
        for probe in probes {
            let matched = blocking.contains { rule in
                guard let regex = try? NSRegularExpression(pattern: rule.trigger.urlFilter) else { return false }
                return regex.firstMatch(in: probe, range: NSRange(probe.startIndex..., in: probe)) != nil
            }
            #expect(matched, "tracker rule for \(probe) did not survive budgeting")
        }
    }

    @Test("EasyPrivacy converts")
    func easyPrivacyConverts() throws {
        let text = try String(contentsOf: DownloadedLists.easyPrivacy, encoding: .utf8)
        let result = AdblockFilterConverter.convert(text)
        print("EasyPrivacy: \(result.converted) converted, \(result.skipped) skipped")
        #expect(result.converted > 2_000)
    }

    @Test("Known tracker domains survive conversion into matching rules")
    func knownTrackersAreCovered() throws {
        let text = try String(contentsOf: DownloadedLists.easyPrivacy, encoding: .utf8)
        let rules = AdblockFilterConverter.convert(text).rules

        // A spot check that the pipeline produces rules that actually match real request
        // URLs, rather than merely producing a large number of well-formed ones.
        let probes = [
            "https://www.google-analytics.com/analytics.js",
            "https://connect.facebook.net/en_US/fbevents.js",
        ]

        let blocking = rules.filter { $0.action.type == "block" }
        for probe in probes {
            let matched = blocking.contains { rule in
                guard let regex = try? NSRegularExpression(pattern: rule.trigger.urlFilter) else { return false }
                return regex.firstMatch(in: probe, range: NSRange(probe.startIndex..., in: probe)) != nil
            }
            #expect(matched, "no rule matched \(probe)")
        }
    }
}
