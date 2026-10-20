// SPDX-License-Identifier: GPL-3.0-or-later
import AppKit
import ShinobiKit

/// A single tab in the tab strip.
///
/// Drawn rather than composed from controls, because the whole strip needs to stay legible
/// at 26pt tall with a hairline vocabulary, and stock `NSButton` chrome fights that.
@MainActor
final class TabItemView: NSView {

    var title: String = "" {
        didSet {
            toolTip = title            // the full title, for when the tab is too narrow
            needsDisplay = true
        }
    }
    var isSelected: Bool = false { didSet { needsDisplay = true } }
    /// Colour of the identity this tab is bound to, drawn as a bar on the leading edge.
    /// This is the always-visible, per-tab half of the identity signal; the toolbar strip
    /// is the other half.
    ///
    /// It sits on the edge rather than inline because the favicon has the better claim on
    /// the inline slot: recognising a site at a glance across twenty tabs is what actually
    /// speeds up the work, and the identity signal loses nothing by moving outward.
    var identityColor: NSColor = Palette.textSecondary { didSet { needsDisplay = true } }
    var favicon: NSImage? { didSet { needsDisplay = true } }

    /// Too narrow for a title. Shows the icon and the identity colour only, which is what
    /// still distinguishes one tab from another at this size.
    var isCompact: Bool = false { didSet { needsDisplay = true } }

    var onSelect: (() -> Void)?
    var onClose: (() -> Void)?

    private var isHovered = false { didSet { needsDisplay = true } }
    private var isCloseHovered = false { didSet { needsDisplay = true } }

    private let horizontalInset: CGFloat = 10
    private let identityBarWidth: CGFloat = 3
    private let faviconSize: CGFloat = 16
    private let closeSize: CGFloat = 18

    override var isFlipped: Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeInKeyWindow, .inVisibleRect],
            owner: self
        ))
    }

    override func mouseEntered(with event: NSEvent) { isHovered = true }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        isCloseHovered = false
    }

    override func mouseMoved(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        isCloseHovered = closeButtonRect.contains(point)
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if showsCloseButton, closeButtonRect.contains(point) {
            onClose?()
        } else {
            onSelect?()
        }
    }

    /// Middle-click closes, matching every other browser.
    override func otherMouseUp(with event: NSEvent) {
        guard event.buttonNumber == 2 else { return }
        onClose?()
    }

    private var showsCloseButton: Bool { isSelected || isHovered }

    private var closeButtonRect: NSRect {
        NSRect(
            x: bounds.maxX - horizontalInset - closeSize,
            y: (bounds.height - closeSize) / 2,
            width: closeSize,
            height: closeSize
        )
    }

    override func draw(_ dirtyRect: NSRect) {
        // Fill. The selected tab is the only one that reads as a raised surface; the rest
        // sit flush with the strip.
        if isSelected {
            Palette.raisedBackground.setFill()
            bounds.fill()
            Palette.accent.setFill()
            NSRect(x: 0, y: 0, width: bounds.width, height: 2).fill()
        } else if isHovered {
            Palette.raisedBackground.withAlphaComponent(0.4).setFill()
            bounds.fill()
        }

        // Trailing hairline, suppressed next to the selected tab so the raised surface
        // reads as continuous.
        if !isSelected {
            Palette.separator.setFill()
            NSRect(x: bounds.maxX - 1, y: 6, width: 1, height: bounds.height - 12).fill()
        }

        // Identity identity, on the leading edge.
        identityColor.setFill()
        NSRect(x: 0, y: 0, width: identityBarWidth, height: bounds.height).fill()

        var textX = identityBarWidth + horizontalInset

        // Favicon, or a neutral placeholder holding the slot so titles do not shift
        // horizontally when an icon arrives.
        let iconRect = NSRect(
            x: isCompact ? (bounds.width - faviconSize) / 2 : textX,
            y: (bounds.height - faviconSize) / 2,
            width: faviconSize,
            height: faviconSize
        )
        if let favicon {
            favicon.draw(in: iconRect, from: .zero, operation: .sourceOver, fraction: isSelected ? 1.0 : 0.75)
        } else {
            Palette.separator.setFill()
            NSBezierPath(roundedRect: iconRect.insetBy(dx: 3, dy: 3), xRadius: 2, yRadius: 2).fill()
        }
        textX = iconRect.maxX + 8

        // At compact width the title would be two or three characters, which identifies
        // nothing; the favicon and the identity bar do the work instead.
        if isCompact {
            if showsCloseButton { drawCloseButton() }
            return
        }

        // Title, truncated at the tail so the leading words — usually the identifying ones —
        // survive.
        let trailingReserve = showsCloseButton ? closeSize + horizontalInset + 6 : horizontalInset
        let textRect = NSRect(
            x: textX,
            y: 0,
            width: max(0, bounds.width - textX - trailingReserve),
            height: bounds.height
        )

        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byTruncatingTail

        let attributes: [NSAttributedString.Key: Any] = [
            .font: isSelected ? Typography.bodyEmphasised : Typography.body,
            .foregroundColor: isSelected ? Palette.textPrimary : Palette.textSecondary,
            .paragraphStyle: style,
        ]
        let attributed = NSAttributedString(string: title, attributes: attributes)
        let textHeight = attributed.size().height
        attributed.draw(in: textRect.insetBy(dx: 0, dy: (textRect.height - textHeight) / 2))

        if showsCloseButton {
            drawCloseButton()
        }
    }

    private func drawCloseButton() {
        let rect = closeButtonRect

        if isCloseHovered {
            Palette.separator.setFill()
            NSBezierPath(roundedRect: rect, xRadius: 3, yRadius: 3).fill()
        }

        let glyph = rect.insetBy(dx: 5.5, dy: 5.5)
        let path = NSBezierPath()
        path.move(to: NSPoint(x: glyph.minX, y: glyph.minY))
        path.line(to: NSPoint(x: glyph.maxX, y: glyph.maxY))
        path.move(to: NSPoint(x: glyph.maxX, y: glyph.minY))
        path.line(to: NSPoint(x: glyph.minX, y: glyph.maxY))
        path.lineWidth = 1.2
        path.lineCapStyle = .round
        (isCloseHovered ? Palette.textPrimary : Palette.textSecondary).setStroke()
        path.stroke()
    }
}
