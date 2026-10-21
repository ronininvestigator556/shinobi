// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

/// Finds out whether a page has been archived, and where.
///
/// Worth its own feature rather than just a pivot link because the answer is often the point:
/// a page that has changed since it was archived, or that exists only in an archive because
/// it has since been deleted, is frequently the finding an investigation turns on.
public struct ArchiveLookup: Sendable {

    public struct Snapshot: Sendable, Equatable {
        public let service: String
        public let url: String
        /// When the snapshot was taken, when the service says.
        public let timestamp: Date?
        public var displayDate: String {
            timestamp.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? "date unknown"
        }
    }

    public struct Result: Sendable, Equatable {
        public var pageURL: String
        /// The most recent snapshot the Wayback Machine reports, if any.
        public var wayback: Snapshot?
        /// Services that were not queried and must be opened to find out.
        public var unqueried: [(service: String, url: String)]

        public static func == (lhs: Result, rhs: Result) -> Bool {
            lhs.pageURL == rhs.pageURL && lhs.wayback == rhs.wayback
                && lhs.unqueried.map(\.service) == rhs.unqueried.map(\.service)
        }
    }

    private let timeout: TimeInterval

    public init(timeout: TimeInterval = 15) {
        self.timeout = timeout
    }

    /// Asks the Wayback Machine what it holds, and assembles links for the services that
    /// have no queryable API.
    ///
    /// The lookup itself discloses the URL to the Internet Archive. That is a small
    /// disclosure and usually an acceptable one, but it is a disclosure, and it is made
    /// through the caller's session so it at least leaves from the container the investigator
    /// is working as.
    public func lookUp(_ pageURL: URL, using session: URLSession) async -> Result {
        var result = Result(
            pageURL: pageURL.absoluteString,
            wayback: nil,
            unqueried: Self.browsableServices(for: pageURL)
        )
        result.wayback = await waybackSnapshot(for: pageURL, using: session)
        return result
    }

    private func waybackSnapshot(for pageURL: URL, using session: URLSession) async -> Snapshot? {
        var components = URLComponents(string: "https://archive.org/wayback/available")
        components?.queryItems = [URLQueryItem(name: "url", value: pageURL.absoluteString)]
        guard let endpoint = components?.url else { return nil }

        var request = URLRequest(url: endpoint)
        request.timeoutInterval = timeout

        guard let (data, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let snapshots = payload["archived_snapshots"] as? [String: Any],
              let closest = snapshots["closest"] as? [String: Any],
              closest["available"] as? Bool == true,
              let url = closest["url"] as? String
        else { return nil }

        return Snapshot(
            service: "Wayback Machine",
            url: url,
            timestamp: (closest["timestamp"] as? String).flatMap(Self.parseWaybackTimestamp)
        )
    }

    /// Wayback stamps are `yyyyMMddHHmmss` in UTC.
    static func parseWaybackTimestamp(_ raw: String) -> Date? {
        guard raw.count == 14 else { return nil }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMddHHmmss"
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.date(from: raw)
    }

    /// Services with no public availability API. Listed as links rather than queried, because
    /// guessing at their contents would be worse than saying "look and see".
    ///
    /// The Memento aggregator used to be here and was removed: timetravel.mementoweb.org no
    /// longer responds. An offer to check an archive that cannot be reached is worse than not
    /// offering it, because it reads as "nothing was archived".
    static func browsableServices(for pageURL: URL) -> [(service: String, url: String)] {
        let encoded = pageURL.absoluteString.addingPercentEncoding(
            withAllowedCharacters: .alphanumerics.union(.init(charactersIn: "-._~"))) ?? ""
        return [
            ("Wayback Machine — all captures", "https://web.archive.org/web/*/\(pageURL.absoluteString)"),
            ("archive.today", "https://archive.ph/newest/\(pageURL.absoluteString)"),
            ("Bing cache", "https://www.bing.com/search?q=url%3A\(encoded)"),
        ]
    }

    /// The URL that asks the Wayback Machine to archive a page now.
    ///
    /// Kept separate from lookup, and never invoked without asking, because it is a
    /// fundamentally different act: it tells the Internet Archive to fetch the page, and the
    /// resulting capture is **public**. Archiving a subject's page can therefore reveal that
    /// someone is looking at it, and does so permanently and to anyone.
    public static func saveRequestURL(for pageURL: URL) -> URL? {
        URL(string: "https://web.archive.org/save/\(pageURL.absoluteString)")
    }
}
