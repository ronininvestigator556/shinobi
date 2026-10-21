// SPDX-License-Identifier: GPL-3.0-or-later
import AppKit

/// Shinobi's colour tokens.
///
/// The reference is Safari and the system: Shinobi should feel native in both light and dark
/// appearance, so the surface, structure, and text tokens are **appearance-aware** — each
/// resolves to a light or dark value depending on the view's effective appearance. The
/// saturated tokens (accent, the three status signals, the identity colours) carry meaning
/// and stay constant across appearances so a signal never changes meaning when the user
/// switches mode.
///
/// Tokens are named by role, never by appearance.
@MainActor
public enum Palette {

    // MARK: Surfaces

    /// Window background and sidebar. The base plane.
    public static let windowBackground = dynamic(light: 0xECECEE, dark: 0x1C1C1E)
    /// Inspector and toolbar. One step forward from the base plane.
    public static let panelBackground = dynamic(light: 0xF5F5F7, dark: 0x242426)
    /// Inset lists, hash fields, the capture ledger. Recessed below the base plane.
    public static let wellBackground = dynamic(light: 0xE3E3E6, dark: 0x161618)
    /// Buttons and tabs at rest. One step above the panel.
    public static let raisedBackground = dynamic(light: 0xFFFFFF, dark: 0x2E2E30)

    // MARK: Structure

    /// 1pt hairlines. Shinobi separates regions with lines, not with shadows or gaps.
    public static let separator = dynamic(light: 0xD1D1D6, dark: 0x3A3A3C)

    // MARK: Text

    public static let textPrimary = dynamic(light: 0x1C1C1E, dark: 0xE8E8EA)
    public static let textSecondary = dynamic(light: 0x6C6C70, dark: 0x8E8E93)
    /// Disabled controls and placeholder text.
    public static let textTertiary = dynamic(light: 0xAEAEB2, dark: 0x5E5E63)

    // MARK: Accent

    /// Selection, active tab, focus ring. Constant across appearances.
    public static let accent = NSColor(hex: 0x2F7DD1)

    // MARK: Status
    //
    // These three carry real meaning in an evidentiary tool and must never be used
    // decoratively. Green means the capture pipeline is running or an artifact verified.
    // Amber means a leak or integrity concern. Red means identity breach or hash mismatch.
    // Constant across appearances so the signal never shifts meaning with the mode.

    /// Capturing, or integrity verified.
    public static let statusCapture = NSColor(hex: 0x3FB950)
    /// Leak or integrity warning.
    public static let statusWarn = NSColor(hex: 0xD29922)
    /// Identity breach or hash mismatch.
    public static let statusAlert = NSColor(hex: 0xDA3633)

    // MARK: Identity colour

    /// The colour assigned to an identity.
    ///
    /// Cases are named rather than indexed into an array, because an identity's colour is
    /// persisted to disk and must survive edits to this palette. An index would silently
    /// recolour every saved identity the moment an entry was inserted — and an identity
    /// that changes colour between launches defeats the entire point of the signal.
    public static func color(for identity: IdentityColor) -> NSColor {
        switch identity {
        case .blue: NSColor(hex: 0x2F7DD1)
        case .green: NSColor(hex: 0x3FB950)
        case .amber: NSColor(hex: 0xD29922)
        case .red: NSColor(hex: 0xDA3633)
        case .violet: NSColor(hex: 0xA371F7)
        case .cyan: NSColor(hex: 0x39C5CF)
        case .magenta: NSColor(hex: 0xDB61A2)
        case .grey: NSColor(hex: 0x8E8E93)
        }
    }

    /// Builds an appearance-aware colour from two 0xRRGGBB literals. The returned colour
    /// resolves to `light` under Aqua and `dark` under Dark Aqua, so a view that uses it
    /// directly updates for free when the system appearance changes. (Values pushed into a
    /// CALayer as `cgColor` still need re-resolving on `viewDidChangeEffectiveAppearance`,
    /// since a layer holds a resolved colour, not the dynamic one.)
    public static func dynamic(light: UInt32, dark: UInt32) -> NSColor {
        NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return NSColor(hex: isDark ? dark : light)
        }
    }
}

/// An identity's identifying colour.
///
/// Chosen to stay legible against `windowBackground` and to remain distinguishable under
/// the common forms of colour blindness — an investigator misreading which identity they
/// are operating as is the most expensive mistake this interface can cause. The set is
/// deliberately small for the same reason: eight colours a person can tell apart beat
/// twenty they cannot.
public enum IdentityColor: String, Codable, CaseIterable, Sendable {
    case blue, green, amber, red, violet, cyan, magenta, grey

    /// The colour offered to the next new identity, cycling through the palette so that
    /// identities created in sequence are visually distinct without the user choosing.
    public static func suggested(forExistingCount count: Int) -> IdentityColor {
        let ordered = allCases.filter { $0 != .grey }   // grey is reserved for the unproxied default
        return ordered[count % ordered.count]
    }
}

extension NSColor {
    /// Builds a colour from a 0xRRGGBB literal in the sRGB space.
    ///
    /// Deliberately sRGB rather than `deviceRGB`: the tokens above are specified as exact
    /// hex values and must render identically across a laptop panel and an external display.
    public convenience init(hex: UInt32, alpha: CGFloat = 1.0) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255.0,
            green: CGFloat((hex >> 8) & 0xFF) / 255.0,
            blue: CGFloat(hex & 0xFF) / 255.0,
            alpha: alpha
        )
    }
}
