// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

/// One rule in WebKit's content-blocking format.
///
/// WebKit applies these in its network process, before a request is made and without any
/// JavaScript in the page. That is why Shinobi blocks natively rather than shipping an
/// extension: uBlock Origin cannot run on WebKit at all, and a JS-based blocker is both
/// slower and observable by the page it is blocking for.
public struct ContentRule: Codable, Equatable, Sendable {

    public struct Trigger: Codable, Equatable, Sendable {
        /// An ICU regular expression matched against the request URL.
        public var urlFilter: String
        public var urlFilterIsCaseSensitive: Bool?
        public var resourceType: [String]?
        public var loadType: [String]?
        public var ifDomain: [String]?
        public var unlessDomain: [String]?

        enum CodingKeys: String, CodingKey {
            case urlFilter = "url-filter"
            case urlFilterIsCaseSensitive = "url-filter-is-case-sensitive"
            case resourceType = "resource-type"
            case loadType = "load-type"
            case ifDomain = "if-domain"
            case unlessDomain = "unless-domain"
        }
    }

    public struct Action: Codable, Equatable, Sendable {
        public var type: String
        public var selector: String?
    }

    public var trigger: Trigger
    public var action: Action
}
