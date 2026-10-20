// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import WebKit

/// Pulls the readable text out of a loaded page.
///
/// Uses `innerText` rather than `textContent`, deliberately. `textContent` returns everything
/// in the DOM including script bodies, hidden templates and markup the visitor never saw;
/// `innerText` returns what was actually rendered. For a record meant to stand as an account
/// of what an investigator looked at, "what was on the screen" is the honest definition.
@MainActor
enum PageTextExtractor {

    /// Upper bound on stored text, in characters.
    ///
    /// Generous enough for a long filing or a whole forum thread, small enough that one
    /// pathological page cannot put a hundred megabytes into a case file.
    static let maximumCharacters = 1_000_000

    static func extract(from webView: WKWebView) async -> String? {
        let result = try? await webView.callAsyncJavaScript(
            script,
            arguments: ["maxChars": maximumCharacters],
            contentWorld: .defaultClient
        )

        guard let text = result as? String else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static let script = """
    const body = document.body;
    if (!body) return null;

    let text = body.innerText || '';
    if (text.length > maxChars) {
        text = text.slice(0, maxChars);
    }
    return text;
    """
}
