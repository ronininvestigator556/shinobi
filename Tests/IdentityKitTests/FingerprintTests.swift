// SPDX-License-Identifier: GPL-3.0-or-later
import WebKit
import Testing

@testable import IdentityKit

/// The fingerprint shim is anonymity-critical: if it is not seeded per identity, two
/// identities share a canvas/WebGL fingerprint and the compartmentalisation leaks across
/// the one surface the data-store split cannot cover.
@MainActor
@Suite("Fingerprint defence")
struct FingerprintTests {

    @Test("The shim is deterministic for a seed and differs across seeds")
    func deterministicPerSeed() {
        let a1 = IdentitySessionProvider.fingerprintShim(seed: 123).source
        let a2 = IdentitySessionProvider.fingerprintShim(seed: 123).source
        let b = IdentitySessionProvider.fingerprintShim(seed: 456).source
        #expect(a1 == a2)
        #expect(a1 != b)
    }

    @Test("The shim hooks the canvas and WebGL fingerprint surfaces")
    func hooksSurfaces() {
        let source = IdentitySessionProvider.fingerprintShim(seed: 1).source
        #expect(source.contains("getImageData"))
        #expect(source.contains("toDataURL"))
        #expect(source.contains("getParameter"))
        #expect(source.contains("37445"))   // UNMASKED_VENDOR_WEBGL
        #expect(source.contains("37446"))   // UNMASKED_RENDERER_WEBGL
    }

    @Test("It injects at document start, into every frame")
    func injectionPlacement() {
        let script = IdentitySessionProvider.fingerprintShim(seed: 1)
        #expect(script.injectionTime == .atDocumentStart)
        #expect(script.isForMainFrameOnly == false)
    }

    @Test("An identity's seed is stable and differs between identities")
    func seedStability() {
        let a = Identity(name: "A", color: .blue)
        #expect(a.fingerprintSeed == a.fingerprintSeed)
        let b = Identity(name: "B", color: .green)
        #expect(a.fingerprintSeed != b.fingerprintSeed)
    }
}
