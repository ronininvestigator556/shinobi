// SPDX-License-Identifier: GPL-3.0-or-later
import AppKit
import WebKit

/// Fetches a page's favicon **from inside the page itself**.
///
/// The obvious implementation — resolve `/favicon.ico` and pull it with a `URLSession` —
/// is disqualified here. A side-channel request made outside the web view would bypass the
/// tab's identity: it would leave on the machine's own connection rather than the
/// identity's proxy, and would carry the app's default cookie jar rather than the
/// identity's. An investigator browsing a subject's site through a proxied sock-puppet
/// identity would be disclosing their real IP to that site's server, for a decoration.
///
/// Running the fetch in page context instead means the request inherits the identity's
/// proxy, TLS session and origin automatically, and keeps working unchanged when Phase 1
/// gives every identity its own data store. Credentials are omitted regardless — an icon
/// never needs the session cookie.
@MainActor
enum FaviconLoader {

    /// Cache keyed by host. Favicons change rarely and a great many tabs share a host, so
    /// this avoids re-running the fetch on every navigation within a site.
    private static var cache: [String: NSImage] = [:]

    /// The largest icon worth decoding. Guards against a site serving a multi-megabyte PNG
    /// as its icon.
    private static let maximumBytes = 512 * 1024

    static func cachedIcon(forHost host: String) -> NSImage? { cache[host] }

    /// Extracts the favicon for the page currently loaded in `webView`.
    ///
    /// Returns `nil` whenever anything goes wrong — a missing icon, a CSP that blocks the
    /// fetch, an undecodable payload. A missing favicon is a cosmetic loss, so every
    /// failure path here is silent by design.
    static func load(from webView: WKWebView) async -> NSImage? {
        guard let host = webView.url?.host else { return nil }
        if let cached = cache[host] { return cached }

        let result = try? await webView.callAsyncJavaScript(
            script,
            arguments: ["maxBytes": maximumBytes],
            contentWorld: .defaultClient
        )

        guard
            let dataURLString = result as? String,
            let dataURL = URL(string: dataURLString),
            let data = try? Data(contentsOf: dataURL),
            let image = NSImage(data: data)
        else { return nil }

        image.size = NSSize(width: 16, height: 16)
        cache[host] = image
        return image
    }

    /// Picks the best declared icon, falling back to `/favicon.ico`, and returns it as a
    /// `data:` URL. Runs in an isolated content world so it cannot be observed by, or
    /// collide with, the page's own scripts.
    private static let script = """
    const declared = Array.from(
        document.querySelectorAll('link[rel~="icon" i], link[rel~="apple-touch-icon" i]')
    );

    // Prefer something near 48pt: large enough to stay sharp on Retina at 16pt, small
    // enough that we are not decoding a launch image.
    const preferredSize = 48;
    const scoreOf = (element) => {
        const declaredSize = parseInt((element.getAttribute('sizes') || '').split(/[x\\u00d7]/)[0], 10);
        return -Math.abs((Number.isNaN(declaredSize) ? 16 : declaredSize) - preferredSize);
    };

    let best = null;
    let bestScore = -Infinity;
    for (const element of declared) {
        const href = element.getAttribute('href');
        if (!href) continue;
        const score = scoreOf(element);
        if (score > bestScore) {
            bestScore = score;
            try { best = new URL(href, document.baseURI).href; } catch (_) { /* skip */ }
        }
    }
    if (!best) {
        try { best = new URL('/favicon.ico', document.baseURI).href; } catch (_) { return null; }
    }

    try {
        const response = await fetch(best, { credentials: 'omit', cache: 'force-cache' });
        if (!response.ok) return null;
        const blob = await response.blob();
        if (blob.size === 0 || blob.size > maxBytes) return null;
        return await new Promise((resolve) => {
            const reader = new FileReader();
            reader.onloadend = () => resolve(reader.result);
            reader.onerror = () => resolve(null);
            reader.readAsDataURL(blob);
        });
    } catch (_) {
        return null;
    }
    """
}
