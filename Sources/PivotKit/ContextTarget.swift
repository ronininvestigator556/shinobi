// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import WebKit

/// What was under the pointer when the context menu opened.
///
/// WebKit does not tell a macOS host what was right-clicked, so a small script listens for
/// `contextmenu` in the page and reports the element and the current selection just before
/// the menu is built. Running in the page rather than hit-testing from the host also means it
/// works for the cases hit-testing gets wrong: an image inside a link, text selected across
/// several elements, an element inside a shadow root.
public struct ContextTarget: Sendable, Equatable {
    public var selection: String = ""
    public var linkURL: String?
    public var imageURL: String?
    /// Text of the link, when one was clicked. Often the more useful thing to pivot on.
    public var linkText: String?

    public var isEmpty: Bool {
        selection.isEmpty && linkURL == nil && imageURL == nil
    }

    public init() {}

    public init(message: [String: Any]) {
        selection = (message["selection"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        linkURL = (message["linkURL"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        imageURL = (message["imageURL"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        linkText = (message["linkText"] as? String).flatMap { $0.isEmpty ? nil : $0 }
    }

    public static let messageName = "shinobiContextTarget"

    /// Reports the context of every right-click.
    ///
    /// Registered in the capture phase so the page cannot swallow the event first — plenty of
    /// sites call `preventDefault` on `contextmenu`, and an investigator needs the pivot menu
    /// most on exactly the kind of site that does that.
    @MainActor
    public static let script = WKUserScript(
        source: """
        document.addEventListener('contextmenu', (event) => {
            const target = event.target;
            const link = target.closest ? target.closest('a[href]') : null;
            const image = target.closest ? target.closest('img[src]') : null;

            let selection = '';
            try { selection = String(window.getSelection()); } catch (_) { selection = ''; }

            window.webkit.messageHandlers.\(messageName).postMessage({
                selection: selection,
                linkURL: link ? link.href : '',
                linkText: link ? (link.textContent || '').trim().slice(0, 300) : '',
                imageURL: image ? image.currentSrc || image.src : ''
            });
        }, true);
        """,
        injectionTime: .atDocumentStart,
        forMainFrameOnly: false
    )
}
