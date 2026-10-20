// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import WebKit

/// How much the engine is locked down for a identity.
///
/// Every switch here is a public WebKit control, applied by Apple's own implementation rather
/// than by JavaScript shims a determined site can detect. That is the whole reason to prefer
/// them: `WKSecurityRestrictionMode.maximizeCompatibility` genuinely disables JIT in the
/// engine, where a shim can only pretend.
///
/// **What these buy, and what they do not.** They reduce *attack surface* — less JIT, fewer
/// parsers, fewer features to exploit. They do **not** make the browser harder to
/// fingerprint. Letterboxing, font uniformity and Firefox's `resistFingerprinting` have no
/// WebKit equivalent, and canvas or WebGL noise is only reachable through shims. Conflating
/// the two would be the easiest overclaim available here, so each setting says which of the
/// two it is.
public struct SecurityPolicy: Codable, Equatable, Sendable {

    public enum Preset: String, Codable, Sendable, CaseIterable {
        case standard
        case hardened
        case lockedDown
        case custom

        public var displayName: String {
            switch self {
            case .standard: "Standard"
            case .hardened: "Hardened"
            case .lockedDown: "Locked down"
            case .custom: "Custom"
            }
        }

        public var explanation: String {
            switch self {
            case .standard:
                "Everything enabled. Pages behave as they would in Safari."
            case .hardened:
                "JIT disabled, HTTPS preferred with a warning on failure, media click-to-play. "
                + "Slower on heavy pages; a smaller target."
            case .lockedDown:
                "Lockdown Mode, JavaScript off, HTTPS required. Many sites will not work. "
                + "For opening something from an untrusted source."
            case .custom:
                "Individually chosen."
            }
        }
    }

    /// How hard the engine restricts itself. Mirrors `WKSecurityRestrictionMode`.
    public enum EngineRestriction: String, Codable, Sendable, CaseIterable {
        case none
        /// Disables JIT compilation and increases memory-tagging adoption, while staying
        /// broadly web-compatible.
        case maximiseCompatibility
        /// Apple's Lockdown Mode: maximum restriction, features disabled outright.
        case lockdown

        public var displayName: String {
            switch self {
            case .none: "None"
            case .maximiseCompatibility: "No JIT (compatible)"
            case .lockdown: "Lockdown Mode"
            }
        }
    }

    public enum HTTPSUpgrade: String, Codable, Sendable, CaseIterable {
        case asRequested
        case upgradeWithSilentFallback
        case upgradeWithWarning
        case requireHTTPS

        public var displayName: String {
            switch self {
            case .asRequested: "As requested"
            case .upgradeWithSilentFallback: "Prefer HTTPS"
            case .upgradeWithWarning: "Prefer HTTPS, warn on failure"
            case .requireHTTPS: "Require HTTPS"
            }
        }
    }

    public var preset: Preset
    public var allowsJavaScript: Bool
    public var engineRestriction: EngineRestriction
    public var httpsUpgrade: HTTPSUpgrade
    public var requiresUserActionForMedia: Bool

    /// Safari's fraudulent-site check.
    ///
    /// Kept as its own setting rather than folded into a preset, because it is a privacy
    /// trade rather than a hardening level. The check consults a Safe Browsing service, which
    /// means **visiting a subject's site can disclose that visit to a third party**. Good
    /// protection for ordinary browsing; a poor default for a working identity.
    public var fraudulentSiteWarning: Bool

    public init(
        preset: Preset = .standard,
        allowsJavaScript: Bool = true,
        engineRestriction: EngineRestriction = .none,
        httpsUpgrade: HTTPSUpgrade = .upgradeWithSilentFallback,
        requiresUserActionForMedia: Bool = false,
        fraudulentSiteWarning: Bool = true
    ) {
        self.preset = preset
        self.allowsJavaScript = allowsJavaScript
        self.engineRestriction = engineRestriction
        self.httpsUpgrade = httpsUpgrade
        self.requiresUserActionForMedia = requiresUserActionForMedia
        self.fraudulentSiteWarning = fraudulentSiteWarning
    }

    /// The settings a preset stands for.
    public static func policy(for preset: Preset, fraudulentSiteWarning: Bool = true) -> SecurityPolicy {
        switch preset {
        case .standard, .custom:
            SecurityPolicy(
                preset: preset,
                allowsJavaScript: true,
                engineRestriction: .none,
                httpsUpgrade: .upgradeWithSilentFallback,
                requiresUserActionForMedia: false,
                fraudulentSiteWarning: fraudulentSiteWarning
            )
        case .hardened:
            SecurityPolicy(
                preset: .hardened,
                allowsJavaScript: true,
                engineRestriction: .maximiseCompatibility,
                httpsUpgrade: .upgradeWithWarning,
                requiresUserActionForMedia: true,
                fraudulentSiteWarning: fraudulentSiteWarning
            )
        case .lockedDown:
            SecurityPolicy(
                preset: .lockedDown,
                allowsJavaScript: false,
                engineRestriction: .lockdown,
                httpsUpgrade: .requireHTTPS,
                requiresUserActionForMedia: true,
                fraudulentSiteWarning: fraudulentSiteWarning
            )
        }
    }

    /// Whether the values still match the preset they claim. Used to move a policy to
    /// `custom` the moment a switch is changed, so the label never lies about what is on.
    public var matchesPreset: Bool {
        guard preset != .custom else { return true }
        let reference = Self.policy(for: preset, fraudulentSiteWarning: fraudulentSiteWarning)
        return reference == self
    }

    /// Consequences worth stating before a page fails to load for reasons that look like a bug.
    public var caveats: [String] {
        var notes: [String] = []
        if !allowsJavaScript {
            notes.append("JavaScript is off: most modern sites will not render fully, and "
                + "captured archives will reflect that.")
        }
        if engineRestriction == .lockdown {
            notes.append("Lockdown Mode disables web fonts, some image formats and several "
                + "web technologies outright.")
        }
        if httpsUpgrade == .requireHTTPS {
            notes.append("HTTP-only sites will not load at all.")
        }
        if fraudulentSiteWarning {
            notes.append("Fraudulent-site checking consults a third-party service, so visiting "
                + "a site can disclose that visit to someone other than the site.")
        }
        return notes
    }
}

extension SecurityPolicy {

    /// Applies the policy to the preferences WebKit consults for every navigation.
    @MainActor
    public func apply(to preferences: WKWebpagePreferences) {
        preferences.allowsContentJavaScript = allowsJavaScript

        switch engineRestriction {
        case .none:
            preferences.isLockdownModeEnabled = false
        case .maximiseCompatibility:
            preferences.isLockdownModeEnabled = false
        case .lockdown:
            preferences.isLockdownModeEnabled = true
        }

        // The finer-grained control arrived in macOS 26.5. Where it exists it is preferred,
        // because `maximiseCompatibility` has no equivalent in the older lockdown flag —
        // without it, "no JIT" would have to be approximated by full Lockdown Mode, which
        // breaks far more than it needs to.
        if #available(macOS 26.5, *) {
            preferences.securityRestrictionMode = switch engineRestriction {
            case .none: .none
            case .maximiseCompatibility: .maximizeCompatibility
            case .lockdown: .lockdown
            }
        }

        preferences.preferredHTTPSNavigationPolicy = switch httpsUpgrade {
        case .asRequested: .keepAsRequested
        case .upgradeWithSilentFallback: .automaticFallbackToHTTP
        case .upgradeWithWarning: .userMediatedFallbackToHTTP
        case .requireHTTPS: .errorOnFailure
        }
    }

    /// Applies the parts that live on the configuration rather than on per-page preferences.
    @MainActor
    public func apply(to configuration: WKWebViewConfiguration) {
        configuration.preferences.isFraudulentWebsiteWarningEnabled = fraudulentSiteWarning
        configuration.upgradeKnownHostsToHTTPS = httpsUpgrade != .asRequested
        configuration.mediaTypesRequiringUserActionForPlayback =
            requiresUserActionForMedia ? .all : []
        apply(to: configuration.defaultWebpagePreferences)
    }
}
