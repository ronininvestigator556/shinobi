// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import Network

/// Where a identity's traffic exits.
///
/// Note what is *not* stored here: the password. Proxy credentials live in the Keychain,
/// keyed by identity id (see `ProxyCredentialStore`). Writing them into the same JSON file
/// as the rest of the configuration would put a working credential for the investigator's
/// egress infrastructure in a world-readable plist — a real finding in a tool whose whole
/// premise is not leaking.
public struct ProxySpec: Codable, Sendable, Equatable, Hashable {

    public enum Kind: String, Codable, Sendable, CaseIterable {
        /// HTTP CONNECT. What most commercial residential-proxy vendors speak.
        case http
        /// SOCKS5. What Tor and most VPN SOCKS endpoints speak.
        case socks5

        public var displayName: String {
            switch self {
            case .http: "HTTP"
            case .socks5: "SOCKS5"
            }
        }
    }

    public var kind: Kind
    public var host: String
    public var port: UInt16
    /// Username, when the proxy requires authentication. The password is in the Keychain.
    public var username: String?

    public init(kind: Kind, host: String, port: UInt16, username: String? = nil) {
        self.kind = kind
        self.host = host
        self.port = port
        self.username = username
    }

    public var requiresPassword: Bool { username?.isEmpty == false }

    /// Short form for the identity strip: `SOCKS5 127.0.0.1:9050`.
    public var displayLabel: String { "\(kind.displayName) \(host):\(port)" }

    /// Tor's default SOCKS port, offered as a preset because running investigative traffic
    /// over a local Tor daemon is a common setup.
    public static let tor = ProxySpec(kind: .socks5, host: "127.0.0.1", port: 9050)
}

extension ProxySpec {

    /// Builds the Network-framework configuration WebKit takes.
    ///
    /// Returns `nil` when the host or port cannot form a valid endpoint. That failure is
    /// surfaced rather than swallowed: a identity that silently falls back to a direct
    /// connection because its proxy was malformed is the exact scenario this whole subsystem
    /// exists to prevent, so callers must treat `nil` as "do not load anything".
    public func makeProxyConfiguration(password: String?) -> ProxyConfiguration? {
        let trimmedHost = host.trimmingCharacters(in: .whitespaces)
        guard !trimmedHost.isEmpty, port > 0 else { return nil }

        let endpoint = NWEndpoint.hostPort(
            host: NWEndpoint.Host(trimmedHost),
            port: NWEndpoint.Port(rawValue: port)!
        )

        let configuration: ProxyConfiguration
        switch kind {
        case .http:
            configuration = ProxyConfiguration(httpCONNECTProxy: endpoint, tlsOptions: nil)
        case .socks5:
            configuration = ProxyConfiguration(socksv5Proxy: endpoint)
        }

        if let username, !username.isEmpty, let password, !password.isEmpty {
            configuration.applyCredential(username: username, password: password)
        }

        return configuration
    }
}
