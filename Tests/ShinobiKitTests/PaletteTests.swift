// SPDX-License-Identifier: GPL-3.0-or-later
import AppKit
import Testing

@testable import ShinobiKit

/// The palette is the whole of Shinobi's light/dark support: if a surface or text token
/// does not resolve to a different, correctly-ordered value per appearance, the app cannot
/// look native in both modes. These pin that invariant.
@MainActor
@Suite("Palette appearance")
struct PaletteTests {

    private func resolve(_ color: NSColor, _ appearanceName: NSAppearance.Name) -> NSColor {
        let appearance = NSAppearance(named: appearanceName)!
        var resolved: NSColor!
        appearance.performAsCurrentDrawingAppearance {
            resolved = color.usingColorSpace(.sRGB)
        }
        return resolved
    }

    @Test("Surface tokens resolve lighter under Aqua than under Dark Aqua")
    func surfacesAreLighterInLightMode() {
        for token in [Palette.windowBackground, Palette.panelBackground,
                      Palette.wellBackground, Palette.raisedBackground] {
            let light = resolve(token, .aqua)
            let dark = resolve(token, .darkAqua)
            #expect(light.brightnessComponent > dark.brightnessComponent)
        }
    }

    @Test("Primary text inverts between appearances")
    func textInverts() {
        let light = resolve(Palette.textPrimary, .aqua)
        let dark = resolve(Palette.textPrimary, .darkAqua)
        // Dark text on a light window; light text on a dark window.
        #expect(light.brightnessComponent < 0.3)
        #expect(dark.brightnessComponent > 0.7)
    }

    @Test("Status and accent signals stay constant across appearances")
    func signalsAreConstant() {
        for token in [Palette.accent, Palette.statusCapture, Palette.statusWarn, Palette.statusAlert] {
            let light = resolve(token, .aqua)
            let dark = resolve(token, .darkAqua)
            #expect(abs(light.redComponent - dark.redComponent) < 0.001)
            #expect(abs(light.greenComponent - dark.greenComponent) < 0.001)
            #expect(abs(light.blueComponent - dark.blueComponent) < 0.001)
        }
    }
}
