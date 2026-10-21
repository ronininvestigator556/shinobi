// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import Network

/// What Shinobi observed about where a identity's traffic actually leaves from.
public enum EgressStatus: Sendable, Equatable {

    /// Not checked yet.
    case unknown
    /// A check is in flight.
    case checking
    /// No proxy configured, and this is the Personal identity — expected.
    case direct(address: String)
    /// Proxied, and the observed address differs from the investigator's own.
    case proxied(address: String)
    /// Proxied, but the traffic came out of the investigator's *own* address anyway.
    ///
    /// The failure this whole subsystem exists to catch. A proxy that is configured but not
    /// actually carrying traffic is worse than no proxy at all, because the interface says
    /// the persona is protected while the subject's server is recording a home address.
    case leaking(address: String)
    /// A working identity with no proxy configured at all.
    case unproxied(address: String?)
    /// The check itself failed — offline, proxy refused, service unreachable.
    case failed(reason: String)

    public var observedAddress: String? {
        switch self {
        case .direct(let address), .proxied(let address), .leaking(let address): address
        case .unproxied(let address): address
        case .unknown, .checking, .failed: nil
        }
    }

    /// Whether the investigator should be looking at this right now.
    public var isAlarming: Bool {
        switch self {
        case .leaking: true
        case .unproxied(let address): address != nil
        default: false
        }
    }
}

/// Determines where a identity's traffic actually exits.
///
/// Configuring a proxy and *using* one are different things, and the gap between them is
/// silent: WebKit will happily carry on over the direct connection if a proxy quietly stops
/// carrying traffic. This asks an echo service what address it sees, through the same proxy
/// configuration the identity's web views use, and compares.
public actor EgressChecker {

    /// The service asked what address it sees.
    ///
    /// Deliberately a single, plain-text, well-known endpoint rather than something
    /// bundled or clever. Whatever is used here learns the address it is asked from, which
    /// is precisely what the check is for — but it means the endpoint should be one the
    /// investigator can recognise and swap, not a Shinobi-operated service that would put us
    /// in the middle of every identity's egress.
    public static let defaultEndpoint = URL(string: "https://api.ipify.org")!

    /// Observes the address a request appears to come from, given a proxy configuration.
    ///
    /// Injectable so the decision logic — in particular the leak comparison, which is the
    /// whole point of this type — can be tested without a live proxy and without making
    /// the tests depend on a third-party service being reachable.
    public typealias AddressObserver = @Sendable (ProxyConfiguration?) async throws -> String

    private let endpoint: URL
    private let timeout: TimeInterval
    private let observer: AddressObserver?

    /// The address the investigator's own connection presents.
    ///
    /// Learned by observing the Personal identity in ordinary use rather than by making an
    /// extra unproxied request. Establishing it deliberately would mean disclosing the real
    /// address to the echo service on behalf of a user who may only ever browse proxied.
    private var directAddress: String?

    public init(
        endpoint: URL = EgressChecker.defaultEndpoint,
        timeout: TimeInterval = 12,
        observer: AddressObserver? = nil
    ) {
        self.endpoint = endpoint
        self.timeout = timeout
        self.observer = observer
    }

    /// Seeds the baseline, for tests and for restoring a known address across a relaunch.
    public func setKnownDirectAddress(_ address: String?) { directAddress = address }

    public func knownDirectAddress() -> String? { directAddress }

    public func check(identity: Identity, password: String?) async -> EgressStatus {
        let proxyConfiguration = identity.proxy?.makeProxyConfiguration(password: password)

        if identity.proxy != nil, proxyConfiguration == nil {
            return .failed(reason: "The proxy settings are not usable.")
        }

        let address: String
        do {
            address = try await (observer ?? observedAddress)(proxyConfiguration)
        } catch {
            return .failed(reason: error.localizedDescription)
        }

        guard identity.proxy != nil else {
            // An unproxied identity tells us what the machine's own connection looks like,
            // which is the baseline every proxied check is compared against.
            directAddress = address
            return identity.isPersonal ? .direct(address: address) : .unproxied(address: address)
        }

        if let directAddress, directAddress == address {
            return .leaking(address: address)
        }
        return .proxied(address: address)
    }

    private nonisolated func observedAddress(_ proxy: ProxyConfiguration?) async throws -> String {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = timeout
        // Never reuse a cached answer: a stale address would report a proxy as working long
        // after it stopped.
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        configuration.urlCache = nil
        if let proxy { configuration.proxyConfigurations = [proxy] }

        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }

        let (data, response) = try await session.data(from: endpoint)

        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw CheckError.badResponse
        }
        let text = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.count <= 45 else { throw CheckError.badResponse }
        return text
    }

    enum CheckError: Error, LocalizedError {
        case badResponse

        var errorDescription: String? { "The address-check service did not answer usefully." }
    }
}
