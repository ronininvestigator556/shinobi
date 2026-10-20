// SPDX-License-Identifier: GPL-3.0-or-later
import AppKit

/// Shinobi's type scale.
///
/// The load-bearing rule: **proportional type is chrome, monospaced type is evidence.**
/// Anything that could end up in a report or be read back to opposing counsel — hashes,
/// URLs, IP addresses, headers, timestamps — is set in SF Mono. Anything that is merely
/// interface is set in SF Pro Text. The reader should be able to tell the two apart
/// without reading the words.
@MainActor
public enum Typography {

    // MARK: Chrome

    /// Sidebar rows, tab titles, inspector values.
    public static let body = NSFont.systemFont(ofSize: 13, weight: .regular)
    /// Emphasised rows: the selected case, the active identity.
    public static let bodyEmphasised = NSFont.systemFont(ofSize: 13, weight: .medium)
    /// Section headers in the sidebar and inspector. Uppercased and tracked.
    public static let sectionHeader = NSFont.systemFont(ofSize: 11, weight: .semibold)
    /// Metadata, counts, secondary labels.
    public static let caption = NSFont.systemFont(ofSize: 11, weight: .regular)

    // MARK: Evidence

    /// Hashes, URLs, IPs, headers.
    public static let mono = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
    /// The capture ledger, where alignment across rows matters.
    public static let monoSmall = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)

    // MARK: Metrics
    //
    // Comfort over density.
    //
    // An earlier version of this file argued the opposite, on the grounds that Shinobi is
    // used for eight-hour sittings. That gets the inference backwards. Logic is dense
    // because a mixer has a hundred tracks contending for one screen; Shinobi's sidebar has
    // a dozen items and no such pressure. Long sittings are an argument for legible type
    // and forgiving hit targets, not against them — the cost of cramping shows up as eye
    // strain and misclicks in hour six, and there is no offsetting gain.

    /// Standard list row height.
    public static let rowHeight: CGFloat = 28
    /// Section header row height.
    public static let headerRowHeight: CGFloat = 24
    /// Maximum corner radius anywhere in the interface.
    public static let cornerRadius: CGFloat = 5
    /// Standard horizontal inset for list and panel content.
    public static let contentInset: CGFloat = 12

    /// Tracking applied to `sectionHeader` text, which is always uppercased.
    public static let sectionHeaderTracking: CGFloat = 0.6
}
