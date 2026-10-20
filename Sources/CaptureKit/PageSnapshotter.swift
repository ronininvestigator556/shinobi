// SPDX-License-Identifier: GPL-3.0-or-later
import AppKit
import Foundation
import WebKit

/// Native full-page screenshot and PDF.
///
/// Both come from WebKit itself rather than from stitching viewport captures together. A
/// stitched screenshot has seams, duplicates sticky headers at every boundary, and misses
/// content that reflows during scrolling — all of which are visible in an exhibit and all of
/// which invite the question of what else the tool got wrong.
@MainActor
public enum PageSnapshotter {

    /// Beyond this height WebKit's snapshot becomes unreliable and enormous. Taller pages are
    /// captured to this height, and the shortfall is reported rather than passed off as a
    /// complete image.
    public static let maximumHeight: CGFloat = 20_000

    public struct Snapshot: Sendable {
        public let png: Data
        public let size: CGSize
        /// True when the page was taller than `maximumHeight` and the image is cut short.
        public let truncated: Bool
    }

    public static func screenshot(of webView: WKWebView) async throws -> Snapshot {
        let fullHeight = try await contentHeight(of: webView)
        let width = webView.bounds.width > 0 ? webView.bounds.width : 1280
        let height = min(fullHeight, maximumHeight)

        let configuration = WKSnapshotConfiguration()
        configuration.rect = CGRect(x: 0, y: 0, width: width, height: height)
        // Ask for the whole page rather than the visible viewport.
        configuration.afterScreenUpdates = true
        configuration.snapshotWidth = NSNumber(value: Double(width))

        let image = try await webView.takeSnapshot(configuration: configuration)

        guard
            let tiff = image.tiffRepresentation,
            let bitmap = NSBitmapImageRep(data: tiff),
            let png = bitmap.representation(using: .png, properties: [:])
        else { throw SnapshotError.encodingFailed }

        return Snapshot(png: png, size: image.size, truncated: fullHeight > maximumHeight)
    }

    public static func pdf(of webView: WKWebView) async throws -> Data {
        // A nil rect asks WebKit for the entire page, paginated.
        try await webView.pdf(configuration: WKPDFConfiguration())
    }

    /// The full scrollable height, which is what makes the screenshot full-page rather than
    /// viewport-sized.
    private static func contentHeight(of webView: WKWebView) async throws -> CGFloat {
        let result = try? await webView.evaluateJavaScript("""
            Math.max(
                document.body ? document.body.scrollHeight : 0,
                document.documentElement ? document.documentElement.scrollHeight : 0
            )
            """)
        let height = (result as? NSNumber)?.doubleValue ?? 0
        return height > 0 ? CGFloat(height) : webView.bounds.height
    }

    public enum SnapshotError: Error, LocalizedError {
        case encodingFailed

        public var errorDescription: String? { "The screenshot could not be encoded as PNG." }
    }
}
