// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

/// Holds the filter-list source text each blocking level compiles from.
///
/// Shinobi ships a small starter list and can replace it with the real community lists on
/// request. It does not bundle EasyList outright: the list is tens of thousands of rules
/// that go stale within weeks, and baking a snapshot into the app would leave investigators
/// running whatever was current on build day.
public actor FilterListStore {

    public enum Source: String, Sendable, CaseIterable {
        case easyList
        case easyPrivacy

        public var url: URL {
            switch self {
            case .easyList: URL(string: "https://easylist.to/easylist/easylist.txt")!
            case .easyPrivacy: URL(string: "https://easylist.to/easylist/easyprivacy.txt")!
            }
        }

        public var displayName: String {
            switch self {
            case .easyList: "EasyList"
            case .easyPrivacy: "EasyPrivacy"
            }
        }

        var fileName: String { rawValue + ".txt" }
    }

    private let directory: URL

    public init(directory: URL? = nil) {
        self.directory = directory ?? Self.defaultDirectory()
        try? FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
    }

    static func defaultDirectory() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Shinobi/FilterLists", isDirectory: true)
    }

    /// The lists a blocking level is built from, kept separate so each can be given its own
    /// share of WebKit's rule budget.
    public func sources(for level: BlockingLevel) -> [(name: String, text: String)] {
        switch level {
        case .off:
            return []
        case .standard:
            return communityLists()
        case .strict:
            return communityLists() + [("Strict extras", FilterListStore.strictExtras)]
        }
    }

    private func communityLists() -> [(name: String, text: String)] {
        let downloaded = Source.allCases.compactMap { source -> (String, String)? in
            guard let text = downloadedText(for: source) else { return nil }
            return (source.displayName, text)
        }
        // Fall back rather than block nothing: a fresh install that has never fetched the
        // community lists still gets meaningful coverage.
        return downloaded.isEmpty ? [("Starter list", FilterListStore.starterList)] : downloaded
    }

    private func downloadedText(for source: Source) -> String? {
        try? String(contentsOf: directory.appendingPathComponent(source.fileName), encoding: .utf8)
    }

    public func hasDownloadedLists() -> Bool {
        Source.allCases.contains { downloadedText(for: $0) != nil }
    }

    /// Fetches the current community lists.
    ///
    /// Deliberately a direct request, never through a identity's proxy. Routing it through
    /// a persona's egress would spend that persona's traffic on something unrelated to the
    /// investigation and make its usage pattern distinctive, and the request discloses
    /// nothing about the investigation in the first place.
    @discardableResult
    public func update() async throws -> [Source] {
        var updated: [Source] = []
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 30
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }

        for source in Source.allCases {
            let (data, response) = try await session.data(from: source.url)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                continue
            }
            try data.write(to: directory.appendingPathComponent(source.fileName), options: .atomic)
            updated.append(source)
        }
        return updated
    }
}

extension FilterListStore {

    /// A compact starter list, used until the community lists have been fetched.
    ///
    /// Honestly named: this is a floor, not a substitute for EasyList. It covers the
    /// highest-volume ad and analytics endpoints so that a fresh install is not browsing
    /// completely unprotected.
    static let starterList = """
    ! Shinobi starter list
    ||doubleclick.net^
    ||googlesyndication.com^
    ||googleadservices.com^
    ||google-analytics.com^
    ||googletagmanager.com^
    ||googletagservices.com^
    ||adservice.google.com^
    ||facebook.com/tr^
    ||connect.facebook.net^
    ||analytics.tiktok.com^
    ||ads.tiktok.com^
    ||scorecardresearch.com^
    ||quantserve.com^
    ||adnxs.com^
    ||rubiconproject.com^
    ||pubmatic.com^
    ||openx.net^
    ||criteo.com^
    ||criteo.net^
    ||taboola.com^
    ||outbrain.com^
    ||amazon-adsystem.com^
    ||adsrvr.org^
    ||casalemedia.com^
    ||sharethrough.com^
    ||teads.tv^
    ||smartadserver.com^
    ||moatads.com^
    ||branch.io^
    ||segment.io^
    ||segment.com^
    ||mixpanel.com^
    ||amplitude.com^
    ||fullstory.com^
    ||hotjar.com^
    ||mouseflow.com^
    ||clarity.ms^
    ||sentry-cdn.com^
    ||newrelic.com^
    ||nr-data.net^
    ||bat.bing.com^
    ||hubspot.com^$third-party
    ||optimizely.com^
    ||crazyegg.com^
    ||inspectlet.com^
    ||luckyorange.com^
    """

    /// Additional rules for the strict level: third-party scripts and frames generally.
    static let strictExtras = """
    ! Shinobi strict extras
    ||*^$third-party,script
    ||*^$third-party,subdocument
    """
}
