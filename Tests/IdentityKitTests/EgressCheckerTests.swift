// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import Testing

@testable import IdentityKit

/// The leak check exists to catch one specific, silent failure: a proxy that is configured
/// but not actually carrying traffic. That state is invisible — the interface says the
/// persona is covered while the subject's server records a home address — so the comparison
/// logic is pinned down here rather than left to be discovered in the field.
@Suite("Egress checking")
struct EgressCheckerTests {

    private let home = "203.0.113.7"     // the investigator's own address
    private let exit = "198.51.100.42"   // a proxy's exit address

    private func checker(returning address: String) -> EgressChecker {
        EgressChecker(observer: { _ in address })
    }

    private var proxied: Identity {
        Identity(
            name: "Puppet",
            color: .violet,
            proxy: ProxySpec(kind: .socks5, host: "127.0.0.1", port: 9050)
        )
    }

    @Test("Personal without a proxy reports a direct connection")
    func personalReportsDirect() async {
        let checker = checker(returning: home)
        let status = await checker.check(identity: .personal, password: nil)
        #expect(status == .direct(address: home))
    }

    @Test("Browsing as Personal establishes the baseline for later comparisons")
    func personalEstablishesBaseline() async {
        let checker = checker(returning: home)
        _ = await checker.check(identity: .personal, password: nil)
        // Learned from ordinary use rather than by making an extra unproxied request, which
        // would disclose the real address on behalf of a user who may only browse proxied.
        #expect(await checker.knownDirectAddress() == home)
    }

    @Test("A proxy exiting elsewhere reports as proxied")
    func workingProxyReportsProxied() async {
        let checker = EgressChecker(observer: { proxy in proxy == nil ? "203.0.113.7" : "198.51.100.42" })
        _ = await checker.check(identity: .personal, password: nil)
        let status = await checker.check(identity: proxied, password: nil)
        #expect(status == .proxied(address: exit))
    }

    @Test("A proxy exiting from the investigator's own address is reported as leaking")
    func silentlyBypassedProxyIsCaught() async {
        // The case the whole subsystem is for. A proxy that has quietly stopped carrying
        // traffic looks identical to a working one from inside the app.
        let checker = checker(returning: home)
        _ = await checker.check(identity: .personal, password: nil)
        let status = await checker.check(identity: proxied, password: nil)
        #expect(status == .leaking(address: home))
        #expect(status.isAlarming)
    }

    @Test("Without a baseline, a proxied identity is not accused of leaking")
    func noBaselineMeansNoAccusation() async {
        // If Personal has never been observed there is nothing to compare against, and
        // claiming a leak on no evidence would train the investigator to ignore the warning.
        let checker = checker(returning: exit)
        let status = await checker.check(identity: proxied, password: nil)
        #expect(status == .proxied(address: exit))
    }

    @Test("A working identity with no proxy is flagged, not reported as fine")
    func unproxiedWorkingIdentityIsFlagged() async {
        let checker = checker(returning: home)
        let bare = Identity(name: "Puppet", color: .red)
        let status = await checker.check(identity: bare, password: nil)
        #expect(status == .unproxied(address: home))
        #expect(status.isAlarming)
    }

    @Test("An unusable proxy fails the check instead of falling back")
    func unusableProxyFails() async {
        let checker = checker(returning: home)
        let broken = Identity(
            name: "Broken",
            color: .red,
            proxy: ProxySpec(kind: .socks5, host: "", port: 0)
        )
        let status = await checker.check(identity: broken, password: nil)
        guard case .failed = status else {
            Issue.record("expected .failed, got \(status)")
            return
        }
    }

    @Test("An unreachable service reports as unverified rather than as safe")
    func unreachableServiceFails() async {
        struct Offline: Error {}
        let checker = EgressChecker(observer: { _ in throw Offline() })
        let status = await checker.check(identity: proxied, password: nil)
        guard case .failed = status else {
            Issue.record("expected .failed, got \(status)")
            return
        }
        // Crucially not `.proxied`: an unverifiable proxy must never read as a verified one.
        #expect(status.observedAddress == nil)
    }
}
