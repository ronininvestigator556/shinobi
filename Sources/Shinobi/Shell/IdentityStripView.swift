// SPDX-License-Identifier: GPL-3.0-or-later
import AppKit
import ShinobiKit

/// The full-width strip beneath the toolbar showing which identity the window is
/// operating as, where its traffic exits, and whether capture is running.
///
/// This view is never hideable and has no collapsed state. Knowing which identity you are
/// operating as, at a glance, at all times, is the single most important safety property in
/// the interface — an investigator who posts from the wrong identity has burned a puppet
/// and possibly the case. The strip is tinted with the identity's own colour so the signal
/// survives peripheral vision.
@MainActor
final class IdentityStripView: NSView {

    static let stripHeight: CGFloat = 24

    enum CaptureState {
        case off
        case capturing
        /// Capture is on but something is wrong — a hash mismatch, or a write failure.
        case degraded(String)
    }

    enum EgressState {
        /// Not checked yet, or a check is running.
        case pending(label: String)
        /// No proxy configured, on the Personal identity. Expected.
        case direct(address: String?)
        /// Proxied, and confirmed to be exiting somewhere other than home.
        case proxied(label: String, address: String)
        /// A working identity with no proxy: it browses from the investigator's address.
        case unproxied
        /// Proxied on paper, but the traffic came out of the investigator's own address.
        case leaking(address: String)
        /// The check could not be completed.
        case failed(label: String)
    }

    var containerName: String = "Personal" { didSet { needsDisplay = true } }
    var containerColor: NSColor = Palette.textSecondary { didSet { needsDisplay = true } }
    var egress: EgressState = .pending(label: "Direct") { didSet { needsDisplay = true } }
    var capture: CaptureState = .off { didSet { needsDisplay = true } }

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func draw(_ dirtyRect: NSRect) {
        // Identity colour washed over the panel surface. Low alpha keeps the strip quiet
        // enough to sit under the toolbar all day while still being unmistakable.
        Palette.panelBackground.setFill()
        bounds.fill()
        containerColor.withAlphaComponent(0.16).setFill()
        bounds.fill()

        // Solid colour rule along the leading edge, and a hairline closing the strip off
        // from the web content below.
        containerColor.setFill()
        NSRect(x: 0, y: 0, width: 3, height: bounds.height).fill()
        Palette.separator.setFill()
        NSRect(x: 0, y: bounds.maxY - 1, width: bounds.width, height: 1).fill()

        var x: CGFloat = 12

        x = drawDot(color: containerColor, at: x)
        x = drawText("Identity", at: x, font: Typography.caption, color: Palette.textSecondary)
        x += 4
        x = drawText(containerName, at: x, font: Typography.bodyEmphasised, color: Palette.textPrimary)

        x += 14
        x = drawEgress(at: x)

        drawCaptureStatus()
    }

    // MARK: Segments

    private func drawEgress(at x: CGFloat) -> CGFloat {
        let (symbol, label, color): (String, String, NSColor)
        switch egress {
        case .pending(let value):
            (symbol, label, color) = ("arrow.up.forward", "\(value) · checking…", Palette.textTertiary)
        case .direct(let address):
            (symbol, label, color) = (
                "arrow.up.forward",
                address.map { "Direct · \($0)" } ?? "Direct",
                Palette.textSecondary
            )
        case .proxied(let value, let address):
            (symbol, label, color) = ("arrow.triangle.branch", "\(value) · \(address)", Palette.textPrimary)
        case .unproxied:
            (symbol, label, color) = (
                "exclamationmark.triangle.fill",
                "No proxy — your own address",
                Palette.statusWarn
            )
        case .leaking(let address):
            // The loudest thing the strip can say. A proxy that is configured but not
            // carrying traffic is worse than none, because the interface otherwise implies
            // the persona is covered.
            (symbol, label, color) = (
                "exclamationmark.octagon.fill",
                "LEAKING — exiting from your own address (\(address))",
                Palette.statusAlert
            )
        case .failed(let value):
            (symbol, label, color) = ("exclamationmark.triangle.fill", "\(value) · unverified", Palette.statusWarn)
        }

        var cursor = drawSymbol(symbol, at: x, color: color)
        cursor += 5
        // Exit addresses are evidence, so they are set in mono like every other address.
        cursor = drawText(label, at: cursor, font: Typography.mono, color: color)
        return cursor
    }

    private func drawCaptureStatus() {
        let (label, color): (String, NSColor)
        switch capture {
        case .off:
            (label, color) = ("Not capturing", Palette.textTertiary)
        case .capturing:
            (label, color) = ("Capturing", Palette.statusCapture)
        case .degraded(let reason):
            (label, color) = (reason, Palette.statusAlert)
        }

        let attributes: [NSAttributedString.Key: Any] = [
            .font: Typography.caption,
            .foregroundColor: color,
        ]
        let attributed = NSAttributedString(string: label, attributes: attributes)
        let size = attributed.size()
        let textX = bounds.maxX - 12 - size.width
        attributed.draw(at: NSPoint(x: textX, y: (bounds.height - size.height) / 2))

        // The dot sits ahead of the label and is the part read at a glance.
        let diameter: CGFloat = 6
        let dotRect = NSRect(
            x: textX - 6 - diameter,
            y: (bounds.height - diameter) / 2,
            width: diameter,
            height: diameter
        )
        color.setFill()
        NSBezierPath(ovalIn: dotRect).fill()
    }

    // MARK: Drawing helpers

    private func drawDot(color: NSColor, at x: CGFloat) -> CGFloat {
        let diameter: CGFloat = 7
        let rect = NSRect(
            x: x,
            y: (bounds.height - diameter) / 2,
            width: diameter,
            height: diameter
        )
        color.setFill()
        NSBezierPath(ovalIn: rect).fill()
        return rect.maxX + 7
    }

    private func drawText(_ string: String, at x: CGFloat, font: NSFont, color: NSColor) -> CGFloat {
        let attributed = NSAttributedString(string: string, attributes: [
            .font: font,
            .foregroundColor: color,
        ])
        let size = attributed.size()
        attributed.draw(at: NSPoint(x: x, y: (bounds.height - size.height) / 2))
        return x + size.width
    }

    private func drawSymbol(_ name: String, at x: CGFloat, color: NSColor) -> CGFloat {
        guard let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 9, weight: .medium)) else { return x }
        let tinted = image.tinted(with: color)
        let rect = NSRect(
            x: x,
            y: (bounds.height - tinted.size.height) / 2,
            width: tinted.size.width,
            height: tinted.size.height
        )
        tinted.draw(in: rect)
        return rect.maxX
    }
}

extension NSImage {
    /// Returns a copy of the image filled with `color`, for use in manual `draw(_:)` paths
    /// where `contentTintColor` is not available.
    func tinted(with color: NSColor) -> NSImage {
        let image = NSImage(size: size, flipped: false) { rect in
            color.set()
            rect.fill()
            self.draw(in: rect, from: .zero, operation: .destinationIn, fraction: 1.0)
            return true
        }
        image.isTemplate = false
        return image
    }
}
