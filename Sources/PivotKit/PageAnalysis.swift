// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

/// What a page contains and what it appears to be built on.
public struct PageAnalysis: Sendable, Equatable {

    public struct Link: Sendable, Equatable, Hashable {
        public let url: String
        public let text: String
        public let host: String
        /// False when the link points back at the page's own host.
        public let isExternal: Bool
    }

    public struct Technology: Sendable, Equatable, Hashable {
        public let name: String
        public let category: String
        /// What was actually observed. Shown rather than hidden, because a fingerprint is an
        /// inference and an investigator should be able to judge it.
        public let evidence: String
    }

    public var pageURL: String = ""
    public var links: [Link] = []
    public var emails: [String] = []
    public var images: [String] = []
    public var technologies: [Technology] = []
    /// Response headers, when they could be read.
    public var headers: [String: String] = [:]
    /// Hosts other than the page's own that it loads from or links to.
    public var externalHosts: [String] = []

    public init() {}

    public init(payload: [String: Any]) {
        pageURL = payload["pageURL"] as? String ?? ""

        links = (payload["links"] as? [[String: Any]] ?? []).compactMap { entry in
            guard let url = entry["url"] as? String, let host = entry["host"] as? String
            else { return nil }
            return Link(
                url: url,
                text: (entry["text"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
                host: host,
                isExternal: entry["external"] as? Bool ?? false
            )
        }

        emails = (payload["emails"] as? [String] ?? []).sorted()
        images = payload["images"] as? [String] ?? []
        headers = payload["headers"] as? [String: String] ?? [:]
        externalHosts = (payload["externalHosts"] as? [String] ?? []).sorted()

        technologies = (payload["technologies"] as? [[String: String]] ?? []).compactMap { entry in
            guard let name = entry["name"] else { return nil }
            return Technology(
                name: name,
                category: entry["category"] ?? "Other",
                evidence: entry["evidence"] ?? ""
            )
        }.sorted { ($0.category, $0.name) < ($1.category, $1.name) }
    }

    public var isEmpty: Bool {
        links.isEmpty && emails.isEmpty && images.isEmpty && technologies.isEmpty
    }

    /// Links grouped by host, most-linked first — usually the more useful reading than a flat
    /// list, since what an investigator wants is "who does this site point at".
    public var linksByHost: [(host: String, links: [Link])] {
        Dictionary(grouping: links.filter(\.isExternal), by: \.host)
            .map { (host: $0.key, links: $0.value) }
            .sorted { ($0.links.count, $1.host) > ($1.links.count, $0.host) }
    }
}
