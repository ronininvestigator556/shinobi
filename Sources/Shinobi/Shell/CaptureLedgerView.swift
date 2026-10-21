// SPDX-License-Identifier: GPL-3.0-or-later
import AppKit
import ShinobiKit

/// The one-line ledger strip beneath the web content.
///
/// From Phase 3 this tails the case's append-only capture log — timestamp, event, artifact
/// hash — so the investigator can see, without looking away from the page, that the thing
/// they are reading has been preserved. Until a case store exists it reports the honest
/// state: nothing is being recorded.
@MainActor
final class CaptureLedgerView: NSView {

    static let ledgerHeight: CGFloat = 20

    /// The most recent ledger line, pre-formatted.
    var line: String = "" { didSet { needsDisplay = true } }
    var accent: NSColor = Palette.textTertiary { didSet { needsDisplay = true } }

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func draw(_ dirtyRect: NSRect) {
        // Recessed surface: the ledger is a readout, not a control.
        Palette.wellBackground.setFill()
        bounds.fill()
        Palette.separator.setFill()
        NSRect(x: 0, y: 0, width: bounds.width, height: 1).fill()

        let diameter: CGFloat = 5
        let dotRect = NSRect(
            x: Typography.contentInset,
            y: (bounds.height - diameter) / 2,
            width: diameter,
            height: diameter
        )
        accent.setFill()
        NSBezierPath(ovalIn: dotRect).fill()

        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byTruncatingTail
        let attributed = NSAttributedString(string: line, attributes: [
            .font: Typography.monoSmall,
            .foregroundColor: Palette.textSecondary,
            .paragraphStyle: style,
        ])
        let size = attributed.size()
        attributed.draw(in: NSRect(
            x: dotRect.maxX + 7,
            y: (bounds.height - size.height) / 2,
            width: bounds.width - dotRect.maxX - 7 - Typography.contentInset,
            height: size.height
        ))
    }
}
