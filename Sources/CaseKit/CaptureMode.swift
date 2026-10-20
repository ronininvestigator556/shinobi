// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

/// How much of a browsing session is preserved.
///
/// The default is `continuous`, and that default is deliberate: a capture step you have to
/// remember is a capture step you will forget, and you will forget it on the page that
/// mattered. Every investigator who has lost a page they were sure they had saved is the
/// reason always-on exists.
///
/// The countervailing problem is real too. Preserving four artifacts for every page visited
/// buries the handful that matter in an export, and an exhibit bundle a reader has to sift
/// through is a worse exhibit bundle. `manual` resolves the two rather than trading one for
/// the other: the *trail* is always kept — where you went, when, as whom, and the page's text,
/// which stays searchable — while the heavy exhibits are only made when you ask. Nothing is
/// silently lost, and the export carries only what you chose.
///
/// `paused` is a genuine off switch, for when none of it should be recorded. It is the only
/// mode that can lose something, so the interface says so continuously rather than once.
public enum CaptureMode: String, Codable, Sendable, CaseIterable {

    /// Every page produces text, an HTML archive, a screenshot and a PDF.
    case continuous

    /// Every page is logged and its text kept and indexed. Archives, screenshots and PDFs are
    /// made only on request.
    case manual

    /// Nothing is recorded.
    case paused

    public var displayName: String {
        switch self {
        case .continuous: "Capture everything"
        case .manual: "Log pages, capture on request"
        case .paused: "Paused"
        }
    }

    /// One line, for the identity strip and the ledger.
    public var statusLabel: String {
        switch self {
        case .continuous: "Capturing"
        case .manual: "Logging"
        case .paused: "Not recording"
        }
    }

    public var explanation: String {
        switch self {
        case .continuous:
            "Every page is preserved in full. Nothing can be missed, and exports contain "
            + "everything visited."
        case .manual:
            "Every page is logged and its text kept, so the trail stays complete and "
            + "searchable. Archives, screenshots and PDFs are made only when you ask, so "
            + "exports carry only what you chose."
        case .paused:
            "Nothing is recorded, including the fact that a page was visited. This is the "
            + "only mode that can lose something."
        }
    }

    /// Whether a visit is written at all.
    public var recordsVisits: Bool { self != .paused }

    /// Whether the heavy artifacts are produced without being asked for.
    public var capturesExhibitsAutomatically: Bool { self == .continuous }
}
