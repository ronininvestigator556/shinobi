// SPDX-License-Identifier: GPL-3.0-or-later
import AppKit

public extension NSView {
    /// Sets the view's layer background from an appearance-aware token, resolved under the
    /// view's own effective appearance.
    ///
    /// A bare `layer?.backgroundColor = token.cgColor` resolves the dynamic colour against
    /// `NSAppearance.current`, which during view setup is usually nil and falls back to Aqua
    /// — so dark-mode chrome would come out light. Resolving inside
    /// `performAsCurrentDrawingAppearance` pins it to what this view is actually drawn in.
    /// Pair with an override of `viewDidChangeEffectiveAppearance()` that re-calls this to
    /// track a live light/dark switch.
    func setLayerBackground(_ color: NSColor) {
        wantsLayer = true
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = color.cgColor
        }
    }

    /// Sets the view's layer border colour from an appearance-aware token. See
    /// `setLayerBackground(_:)` for why the appearance context matters.
    func setLayerBorder(_ color: NSColor) {
        wantsLayer = true
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.borderColor = color.cgColor
        }
    }
}
