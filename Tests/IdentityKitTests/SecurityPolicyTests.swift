// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import Testing
import WebKit

@testable import IdentityKit

@Suite("Security policy")
struct SecurityPolicyTests {

    @Test("Presets describe what they actually set")
    func presetsAreCoherent() {
        let standard = SecurityPolicy.policy(for: .standard)
        #expect(standard.allowsJavaScript)
        #expect(standard.engineRestriction == .none)

        let hardened = SecurityPolicy.policy(for: .hardened)
        // Hardened has to stay usable: JavaScript on, JIT off. A "hardened" mode that broke
        // every site would just be switched off and never used.
        #expect(hardened.allowsJavaScript)
        #expect(hardened.engineRestriction == .maximiseCompatibility)
        #expect(hardened.requiresUserActionForMedia)

        let locked = SecurityPolicy.policy(for: .lockedDown)
        #expect(!locked.allowsJavaScript)
        #expect(locked.engineRestriction == .lockdown)
        #expect(locked.httpsUpgrade == .requireHTTPS)
    }

    @Test("Changing a switch stops the policy claiming to be a preset")
    func editingMovesToCustom() {
        var policy = SecurityPolicy.policy(for: .hardened)
        #expect(policy.matchesPreset)

        policy.allowsJavaScript = false
        // A identity labelled "Hardened" while running something else would misinform the
        // investigator about their own posture.
        #expect(!policy.matchesPreset)
    }

    @Test("Each preset states its own consequences")
    func presetsDeclareCaveats() {
        // A page failing to load under a strict policy looks like a bug unless the interface
        // said in advance that it would.
        let locked = SecurityPolicy.policy(for: .lockedDown, fraudulentSiteWarning: false)
        #expect(locked.caveats.contains { $0.contains("JavaScript is off") })
        #expect(locked.caveats.contains { $0.contains("HTTP-only sites will not load") })

        let standard = SecurityPolicy.policy(for: .standard, fraudulentSiteWarning: false)
        #expect(standard.caveats.isEmpty)
    }

    @Test("The fraudulent-site check is declared as a disclosure")
    func safeBrowsingIsDeclared() {
        // It is the one control in this group that leaks rather than protects: the check
        // consults a third-party service, so visiting a subject's site can disclose it.
        let policy = SecurityPolicy.policy(for: .standard, fraudulentSiteWarning: true)
        #expect(policy.caveats.contains { $0.contains("disclose that visit") })
    }

    @Test("A identity saved before security existed still decodes")
    func olderContainersDecode() throws {
        // Upgrading must never silently drop someone's identities.
        let json = """
        {"id":"\(UUID().uuidString)","name":"Legacy","color":"blue",
         "blocking":"standard","createdAt":"2026-09-01T00:00:00Z",
         "userAgent":{"safari":{}}}
        """
        let identity = try JSONDecoder.shinobi().decode(Identity.self, from: Data(json.utf8))
        #expect(identity.name == "Legacy")
        #expect(identity.security.preset == .standard)
    }

    @Test("A policy survives a round trip")
    func policyRoundTrips() throws {
        var policy = SecurityPolicy.policy(for: .lockedDown)
        policy.fraudulentSiteWarning = false
        let identity = Identity(name: "Locked", color: .red, security: policy)

        let decoded = try JSONDecoder.shinobi()
            .decode(Identity.self, from: try JSONEncoder.shinobi().encode(identity))
        #expect(decoded.security == policy)
    }

    @MainActor
    @Test("Applying a policy reaches the WebKit objects that enforce it")
    func policyReachesWebKit() {
        let configuration = WKWebViewConfiguration()
        var policy = SecurityPolicy.policy(for: .lockedDown)
        policy.fraudulentSiteWarning = false
        policy.apply(to: configuration)

        // Asserted against the real objects: a policy that is modelled correctly but never
        // reaches WebKit protects nothing.
        #expect(!configuration.defaultWebpagePreferences.allowsContentJavaScript)
        #expect(configuration.defaultWebpagePreferences.isLockdownModeEnabled)
        #expect(configuration.defaultWebpagePreferences.preferredHTTPSNavigationPolicy == .errorOnFailure)
        #expect(!configuration.preferences.isFraudulentWebsiteWarningEnabled)
        #expect(configuration.mediaTypesRequiringUserActionForPlayback == .all)

        if #available(macOS 26.5, *) {
            #expect(configuration.defaultWebpagePreferences.securityRestrictionMode == .lockdown)
        }
    }

    @MainActor
    @Test("Hardened disables JIT without turning on full Lockdown Mode")
    func hardenedUsesTheFinerControl() {
        let configuration = WKWebViewConfiguration()
        SecurityPolicy.policy(for: .hardened).apply(to: configuration)

        // The distinction that makes Hardened worth having: no JIT, but not the wholesale
        // feature disablement of Lockdown Mode.
        #expect(!configuration.defaultWebpagePreferences.isLockdownModeEnabled)
        #expect(configuration.defaultWebpagePreferences.allowsContentJavaScript)
        if #available(macOS 26.5, *) {
            #expect(configuration.defaultWebpagePreferences.securityRestrictionMode == .maximizeCompatibility)
        }
    }
}
