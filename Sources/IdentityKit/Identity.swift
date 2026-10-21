// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import ShinobiKit

/// An investigative identity.
///
/// A identity is the unit of compartmentalisation in Shinobi: one persona, one cookie jar,
/// one exit address, one user agent. The community consensus on sock puppets is that these
/// must never cross, and the whole point of making a identity a first-class object — rather
/// than a convention the investigator maintains by hand across profiles and VPN toggles — is
/// that crossing them becomes something the software will not do rather than something the
/// user must remember not to do.
///
/// The `id` is load-bearing beyond identification: it is the identifier handed to
/// `WKWebsiteDataStore(forIdentifier:)`, so it names the on-disk cookie and storage
/// directory. It is `let` and never rewritten. Changing it would orphan every session and
/// silently log the persona out of everything.
public struct Identity: Identifiable, Codable, Sendable, Equatable {

    public let id: UUID
    public var name: String
    public var color: IdentityColor

    /// Where this identity's traffic exits. `nil` means the machine's own connection.
    public var proxy: ProxySpec?

    public var userAgent: UserAgentProfile

    /// Timezone reported to page scripts, as an IANA identifier. `nil` leaves the system
    /// timezone in place.
    ///
    /// Best-effort by nature: this is a JavaScript shim over `Intl` and `Date`, not an
    /// engine-level change, and a determined fingerprinter can detect the seam. It is worth
    /// having because a persona claiming to be in Berlin reporting `America/Chicago` fails
    /// the *casual* check that most sites actually perform — but it should never be
    /// described to the user as making them undetectable.
    public var timezone: String?

    public var blocking: BlockingLevel

    /// How far the engine is locked down for this identity.
    public var security: SecurityPolicy

    public let createdAt: Date

    public init(
        id: UUID = UUID(),
        name: String,
        color: IdentityColor,
        proxy: ProxySpec? = nil,
        userAgent: UserAgentProfile = .safari,
        timezone: String? = nil,
        blocking: BlockingLevel = .standard,
        security: SecurityPolicy = SecurityPolicy(),
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.color = color
        self.proxy = proxy
        self.userAgent = userAgent
        self.timezone = timezone
        self.blocking = blocking
        self.security = security
        self.createdAt = createdAt.roundedToPersistedPrecision()
    }

    /// The identity every window starts in: the investigator's own browsing, unproxied and
    /// unspoofed.
    ///
    /// It carries a fixed id so it survives across launches, and is deliberately grey and
    /// named "Personal" — it should not look like one of the working identities, because
    /// mistaking it for one is how an investigator burns their real address.
    ///
    /// The id is an ordinary random UUID rather than a tidy `...0001`. WebKit reserves the
    /// UUIDs whose 128-bit value is 0 or 1 as hash-table sentinels and rejects them outright
    /// (see `WebSessionIdentifier`), so a readable constant here is not merely unfashionable
    /// but unusable.
    public static let personal = Identity(
        id: UUID(uuidString: "4BB214AB-7BAA-4D3A-883C-908E5625D008")!,
        name: "Personal",
        color: .grey
    )

    public var isPersonal: Bool { id == Self.personal.id }

    /// A stable per-identity seed derived from `id`, used to key fingerprint defences so an
    /// identity's canvas/WebGL fingerprint is consistent within itself but differs between
    /// identities and from the real machine. Deterministic across launches — unlike
    /// `Hashable`, which Swift salts per process — because the same bundle opened twice must
    /// present the same identity to a site, or the "stable persona" is a lie.
    public var fingerprintSeed: UInt32 {
        withUnsafeBytes(of: id.uuid) { raw in
            var seed: UInt32 = 2_166_136_261            // FNV-1a
            for byte in raw { seed = (seed ^ UInt32(byte)) &* 16_777_619 }
            return seed
        }
    }

    /// Decoding tolerates identities written before a field existed, so an upgrade never
    /// silently drops someone's identities.
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        name = try values.decode(String.self, forKey: .name)
        color = try values.decode(IdentityColor.self, forKey: .color)
        proxy = try values.decodeIfPresent(ProxySpec.self, forKey: .proxy)
        userAgent = try values.decodeIfPresent(UserAgentProfile.self, forKey: .userAgent) ?? .safari
        timezone = try values.decodeIfPresent(String.self, forKey: .timezone)
        blocking = try values.decodeIfPresent(BlockingLevel.self, forKey: .blocking) ?? .standard
        security = try values.decodeIfPresent(SecurityPolicy.self, forKey: .security) ?? SecurityPolicy()
        createdAt = try values.decode(Date.self, forKey: .createdAt)
    }
}

/// What the identity reports as its user agent.
public enum UserAgentProfile: Codable, Sendable, Equatable, Hashable {

    /// WebKit's own string. The default, and usually the right answer: Shinobi *is* Safari on
    /// macOS underneath, so claiming anything else creates a mismatch between the declared
    /// agent and the engine's observable behaviour that is easier to detect than saying
    /// nothing at all.
    case safari

    /// A stated string, for the cases where a site gates content by platform.
    case custom(String)

    /// Common presets, offered so the user is not hand-typing agent strings.
    public static let presets: [(name: String, profile: UserAgentProfile)] = [
        ("Safari on macOS (native)", .safari),
        ("Chrome on Windows", .custom(
            "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) "
            + "Chrome/140.0.0.0 Safari/537.36"
        )),
        ("Chrome on Android", .custom(
            "Mozilla/5.0 (Linux; Android 15; Pixel 9) AppleWebKit/537.36 (KHTML, like Gecko) "
            + "Chrome/140.0.0.0 Mobile Safari/537.36"
        )),
        ("Safari on iPhone", .custom(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 18_5 like Mac OS X) AppleWebKit/605.1.15 "
            + "(KHTML, like Gecko) Version/18.5 Mobile/15E148 Safari/604.1"
        )),
    ]

    /// The string to hand to `WKWebView.customUserAgent`, or `nil` to leave WebKit's own.
    public var stringValue: String? {
        switch self {
        case .safari: nil
        case .custom(let value): value
        }
    }

    public var displayName: String {
        switch self {
        case .safari: "Safari on macOS (native)"
        case .custom(let value):
            Self.presets.first { $0.profile == self }?.name ?? value
        }
    }
}

/// How aggressively the identity blocks ads and trackers.
public enum BlockingLevel: String, Codable, Sendable, CaseIterable {
    /// No rules. Needed more often than it sounds: blocking changes how a page renders, and
    /// an exhibit should show what an ordinary visitor would have seen.
    case off
    /// Ads and trackers.
    case standard
    /// Ads, trackers, and third-party content generally.
    case strict

    public var displayName: String {
        switch self {
        case .off: "Off"
        case .standard: "Ads and trackers"
        case .strict: "Strict"
        }
    }
}
