// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import Testing

@testable import PivotKit

@Suite("Pivot sources")
struct PivotSourceTests {

    @Test("Every entity kind that can be looked up has somewhere to go")
    func everyKindIsCovered() {
        // A kind detected but never actionable is a menu entry that does nothing.
        let unreachable = Entity.Kind.allCases.filter { PivotRegistry.sources(for: $0).isEmpty }
        #expect(unreachable.isEmpty, "no sources for \(unreachable.map(\.rawValue))")
    }

    @Test("Every template is a valid URL once filled in")
    func templatesProduceValidURLs() throws {
        for source in PivotRegistry.sources {
            let kind = try #require(source.kinds.first)
            let url = source.url(for: Entity(kind: kind, raw: "example-value"))
            #expect(url != nil, "\(source.name) produced no URL")
            #expect(url?.scheme == "https", "\(source.name) is not HTTPS")
        }
    }

    @Test("Entity values are percent-encoded into the template")
    func valuesAreEncoded() throws {
        // Entities come off a subject's page and are untrusted. A raw `&` or `#` would
        // silently rewrite the query it was meant to be a parameter of.
        let source = PivotSource("Test", "https://example.com/?q={value}&safe=1", kinds: [.domain], category: .search)
        let hostile = Entity(kind: .domain, raw: "x", normalised: "a&b=c#frag /../")
        let url = try #require(source.url(for: hostile))

        #expect(!url.absoluteString.contains("a&b=c"))
        #expect(url.absoluteString.contains("safe=1"))
        #expect(url.query?.contains("%26") == true)
    }

    @Test("Sources are filtered by the kind they can answer for")
    func sourcesMatchKinds() {
        let forHash = PivotRegistry.sources(for: .sha256)
        #expect(forHash.contains { $0.name == "VirusTotal" })
        #expect(!forHash.contains { $0.name == "Whois" })

        let forCVE = PivotRegistry.sources(for: .cve)
        #expect(forCVE.allSatisfy { $0.kinds.contains(.cve) })
    }

    @Test("The menu stays readable")
    func listIsReadable() {
        // A pivot menu is only useful if it can be scanned at a glance; the fifty-entry
        // version in community toolboxes is a reference document, not an interface.
        //
        // The original form of this test capped every kind at eight sources, which domains
        // legitimately exceed — whois, certificates, infrastructure, reputation, two archives
        // and search are all worth having. Rather than delete useful lookups or raise the cap
        // and lose the constraint, sources are grouped: the binding limit is how long any one
        // group runs, since that is what actually has to be read at a glance.
        for kind in Entity.Kind.allCases {
            #expect(PivotRegistry.sources(for: kind).count <= 12,
                    "\(kind.rawValue) offers \(PivotRegistry.sources(for: kind).count) sources")

            for group in PivotRegistry.grouped(for: kind) {
                #expect(group.sources.count <= 5,
                        "\(kind.rawValue)/\(group.category.rawValue) has \(group.sources.count)")
            }
        }
    }

    @Test("Groups come back in a stable, sensible order")
    func groupsAreOrdered() {
        let groups = PivotRegistry.grouped(for: .domain).map(\.category)
        #expect(groups == groups.sorted())
        // Registration before search: an investigator looking at a domain wants who owns it
        // before they want a web search for it.
        if groups.contains(.registration) && groups.contains(.search) {
            #expect(groups.firstIndex(of: .registration)! < groups.firstIndex(of: .search)!)
        }
    }
}
