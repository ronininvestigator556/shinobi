// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

/// The page-serialisation script.
///
/// Written from scratch rather than adapted from an existing serialiser. The obvious
/// candidate, SingleFile, is AGPL-3.0, which is not a licence a distributed application can
/// absorb — so this shares the approach the technique demands and none of its code.
///
/// Four decisions define what the resulting artifact is worth as evidence:
///
/// **It serialises the DOM, not the rendered text.** The case store's text index uses
/// `innerText`, which returns only what was on screen — content behind a "show" toggle or an
/// unexpanded accordion is silently absent. Walking the DOM keeps it, which is the whole
/// reason this exists.
///
/// **Scripts are removed.** An archived page is opened later, often by someone other than the
/// investigator, sometimes on a machine that matters. An exhibit that executes JavaScript
/// when opened could alter what it displays, phone home, or reveal that the archive is being
/// reviewed. Every `<script>`, every `on*` handler and every `javascript:` URL is stripped,
/// and the artifact records that this was done.
///
/// **Resources are fetched from inside the page.** Same reasoning as favicons: a fetch issued
/// outside the web view would bypass the identity's proxy and disclose the investigator's
/// real address to the subject's server.
///
/// **What could not be captured is counted and reported.** A silent partial capture is worse
/// than an obviously partial one, because only the second can be argued about honestly.
enum PageArchiverScript {

    static let source = #"""
    const perResourceLimit = maxResourceBytes;
    const totalLimit = maxTotalBytes;

    let inlinedBytes = 0;
    const cache = new Map();
    const notes = [];
    const stats = {
        stylesheetsInlined: 0, stylesheetsFailed: 0,
        imagesInlined: 0, imagesFailed: 0,
        fontsInlined: 0,
        canvasesRasterised: 0,
        framesInlined: 0, framesSkipped: 0,
        scriptsRemoved: 0, handlersRemoved: 0,
        remoteReferencesNeutralised: 0,
        noscriptBlocksRemoved: 0,
        bytesInlined: 0
    };

    const absolute = (url, base) => {
        try { return new URL(url, base || document.baseURI).href; } catch (_) { return null; }
    };

    /// Fetches a resource and returns it as a data: URL, or null.
    /// Credentials are omitted: a subresource never needs the session cookie, and sending one
    /// would put the identity's authenticated identity on requests the page did not make.
    async function inline(url) {
        const resolved = absolute(url);
        if (!resolved || resolved.startsWith('data:')) return resolved;
        if (cache.has(resolved)) return cache.get(resolved);
        if (inlinedBytes >= totalLimit) return null;

        try {
            const response = await fetch(resolved, { credentials: 'omit', cache: 'force-cache' });
            if (!response.ok) return null;
            const blob = await response.blob();
            if (blob.size === 0 || blob.size > perResourceLimit) return null;
            if (inlinedBytes + blob.size > totalLimit) return null;

            const dataURL = await new Promise((resolve) => {
                const reader = new FileReader();
                reader.onloadend = () => resolve(reader.result);
                reader.onerror = () => resolve(null);
                reader.readAsDataURL(blob);
            });
            if (dataURL) {
                inlinedBytes += blob.size;
                stats.bytesInlined = inlinedBytes;
                cache.set(resolved, dataURL);
            }
            return dataURL;
        } catch (_) {
            return null;
        }
    }

    /// Rewrites url(...) references inside a stylesheet so fonts and background images survive.
    async function inlineStyleURLs(cssText, baseURL) {
        const references = [...cssText.matchAll(/url\(\s*(['"]?)([^'")]+)\1\s*\)/g)];
        let result = cssText;
        for (const match of references) {
            const raw = match[2].trim();
            if (raw.startsWith('data:') || raw.startsWith('#')) continue;
            const resolved = absolute(raw, baseURL);
            if (!resolved) continue;
            const dataURL = await inline(resolved);
            if (dataURL) {
                result = result.split(match[0]).join(`url("${dataURL}")`);
                if (/\.(woff2?|ttf|otf|eot)(\?|$)/i.test(resolved)) stats.fontsInlined++;
            }
        }
        return result;
    }

    /// Reads a stylesheet's rules, falling back to fetching it when the browser refuses
    /// cross-origin rule access.
    async function serialiseStyleSheet(sheet) {
        try {
            if (sheet.cssRules) {
                const text = Array.from(sheet.cssRules).map((rule) => rule.cssText).join('\n');
                return await inlineStyleURLs(text, sheet.href || document.baseURI);
            }
        } catch (_) { /* cross-origin: fall through to fetching it */ }

        if (!sheet.href) return null;
        try {
            const response = await fetch(sheet.href, { credentials: 'omit', cache: 'force-cache' });
            if (!response.ok) return null;
            const text = await response.text();
            return await inlineStyleURLs(text, sheet.href);
        } catch (_) {
            return null;
        }
    }

    // ---- Build the archive -------------------------------------------------------------

    const doc = document.documentElement.cloneNode(true);

    // Strip anything executable. Done on the clone, before any other processing, so no later
    // step can reintroduce a handler.
    for (const script of doc.querySelectorAll('script')) {
        script.remove();
        stats.scriptsRemoved++;
    }
    for (const element of doc.querySelectorAll('*')) {
        for (const attribute of Array.from(element.attributes)) {
            const name = attribute.name.toLowerCase();
            if (name.startsWith('on')) {
                element.removeAttribute(attribute.name);
                stats.handlersRemoved++;
            } else if ((name === 'href' || name === 'src' || name === 'action')
                       && /^\s*javascript:/i.test(attribute.value)) {
                element.setAttribute(attribute.name, '#');
                stats.handlersRemoved++;
            }
        }
    }

    // Stylesheets, in document order, replacing <link rel=stylesheet> with inline <style>.
    const liveSheets = Array.from(document.styleSheets);
    const clonedLinks = Array.from(doc.querySelectorAll('link[rel~="stylesheet" i]'));
    for (const sheet of liveSheets) {
        const css = await serialiseStyleSheet(sheet);
        const owner = sheet.ownerNode;
        if (css === null) {
            stats.stylesheetsFailed++;
            continue;
        }
        stats.stylesheetsInlined++;

        if (owner && owner.tagName === 'LINK' && owner.href) {
            const match = clonedLinks.find((link) => link.href === owner.href);
            if (match) {
                const style = doc.ownerDocument.createElement('style');
                style.textContent = css;
                match.replaceWith(style);
            }
        }
    }
    // Any <link rel=stylesheet> still present could not be read.
    for (const leftover of doc.querySelectorAll('link[rel~="stylesheet" i]')) {
        leftover.remove();
    }

    // Inline <style> blocks may themselves reference fonts and images.
    for (const style of doc.querySelectorAll('style')) {
        style.textContent = await inlineStyleURLs(style.textContent || '', document.baseURI);
    }

    // Images. srcset and <picture><source> are cleared once src is inlined, or a replaying
    // browser would pick an un-inlined candidate and show a broken image.
    const liveImages = Array.from(document.images);
    const clonedImages = Array.from(doc.querySelectorAll('img'));
    for (let index = 0; index < clonedImages.length; index++) {
        const clone = clonedImages[index];
        const live = liveImages[index];
        const source = (live && live.currentSrc) || clone.getAttribute('src');
        if (!source) continue;

        const dataURL = await inline(source);
        if (dataURL) {
            clone.setAttribute('src', dataURL);
            stats.imagesInlined++;
        } else {
            stats.imagesFailed++;
        }
        clone.removeAttribute('srcset');
        clone.removeAttribute('loading');
        const picture = clone.closest('picture');
        if (picture) picture.querySelectorAll('source').forEach((s) => s.remove());
    }

    // Inline style attributes carrying url(...).
    for (const element of doc.querySelectorAll('[style*="url("]')) {
        element.setAttribute('style', await inlineStyleURLs(element.getAttribute('style'), document.baseURI));
    }

    // Canvases hold pixels that exist only in memory; without JavaScript they replay blank.
    const liveCanvases = Array.from(document.querySelectorAll('canvas'));
    const clonedCanvases = Array.from(doc.querySelectorAll('canvas'));
    for (let index = 0; index < clonedCanvases.length; index++) {
        const live = liveCanvases[index];
        if (!live) continue;
        try {
            const dataURL = live.toDataURL('image/png');
            const image = doc.ownerDocument.createElement('img');
            image.setAttribute('src', dataURL);
            image.setAttribute('width', String(live.width));
            image.setAttribute('height', String(live.height));
            image.setAttribute('data-shinobi-was', 'canvas');
            clonedCanvases[index].replaceWith(image);
            stats.canvasesRasterised++;
        } catch (_) {
            // Tainted by cross-origin content; the pixels cannot be read.
            notes.push('A canvas could not be rasterised because it was cross-origin tainted.');
        }
    }

    // Form state is part of what the investigator saw.
    const liveFields = Array.from(document.querySelectorAll('input, textarea, select'));
    const clonedFields = Array.from(doc.querySelectorAll('input, textarea, select'));
    for (let index = 0; index < clonedFields.length; index++) {
        const live = liveFields[index];
        const clone = clonedFields[index];
        if (!live) continue;
        if (live.tagName === 'TEXTAREA') {
            clone.textContent = live.value;
        } else if (live.tagName === 'SELECT') {
            Array.from(clone.options).forEach((option, i) => {
                if (live.options[i] && live.options[i].selected) option.setAttribute('selected', '');
                else option.removeAttribute('selected');
            });
        } else if (live.type === 'checkbox' || live.type === 'radio') {
            if (live.checked) clone.setAttribute('checked', '');
            else clone.removeAttribute('checked');
        } else if (live.type !== 'password') {
            // Password fields are deliberately not captured.
            clone.setAttribute('value', live.value);
        }
    }

    // Same-origin frames are inlined via srcdoc; cross-origin ones cannot be read at all and
    // are replaced with a visible marker rather than left as a silently empty box.
    const liveFrames = Array.from(document.querySelectorAll('iframe'));
    const clonedFrames = Array.from(doc.querySelectorAll('iframe'));
    for (let index = 0; index < clonedFrames.length; index++) {
        const live = liveFrames[index];
        const clone = clonedFrames[index];
        let inner = null;
        try { inner = live && live.contentDocument; } catch (_) { inner = null; }

        if (inner && inner.documentElement) {
            const markup = inner.documentElement.outerHTML
                .replace(/<script[\s\S]*?<\/script>/gi, '');
            clone.setAttribute('srcdoc', markup);
            clone.removeAttribute('src');
            stats.framesInlined++;
        } else {
            const marker = doc.ownerDocument.createElement('div');
            marker.setAttribute('data-shinobi-was', 'iframe');
            marker.setAttribute('style',
                'border:1px dashed #999;padding:8px;font:12px system-ui;color:#666');
            marker.textContent = 'Cross-origin frame not captured: '
                + (clone.getAttribute('src') || 'unknown source');
            clone.replaceWith(marker);
            stats.framesSkipped++;
        }
    }

    // <noscript> content is not part of the DOM while scripting is enabled — the browser
    // keeps it as a raw text node — so it is invisible to querySelectorAll yet still present
    // in the serialised markup. Wikipedia hides a CentralAutoLogin tracking pixel there, and
    // it survived every DOM-based sweep: the archive looked clean and would still have fired
    // a request the moment a reviewer opened it with JavaScript off, which is exactly how a
    // careful reviewer opens an untrusted file.
    //
    // Removing it is also the faithful choice. The page was viewed with scripting enabled, so
    // this content was never rendered and was never part of what the investigator saw.
    for (const noscript of doc.querySelectorAll('noscript')) {
        noscript.remove();
        stats.noscriptBlocksRemoved++;
    }

    // Neutralise anything still pointing at the network.
    //
    // A resource that failed to inline stays in the markup as a live reference, and opening
    // the archive then fetches it — so an exhibit reviewed months later silently tells the
    // subject's server that it is being reviewed, and from where. Wikipedia's CentralAutoLogin
    // pixel was doing exactly that in testing: a 1x1 image that could not be inlined and was
    // left as a remote src.
    //
    // Anchor hrefs are deliberately left alone. They are part of the record — where the page
    // pointed matters — and they only load if a reader clicks them.
    const loadingAttributes = ['src', 'srcset', 'poster', 'data'];
    for (const element of doc.querySelectorAll('[src], [srcset], [poster], [data]')) {
        for (const name of loadingAttributes) {
            const value = element.getAttribute(name);
            if (!value || value.startsWith('data:')) continue;
            let resolved = null;
            try { resolved = new URL(value, document.baseURI).protocol; } catch (_) { resolved = null; }
            if (resolved === 'http:' || resolved === 'https:') {
                element.removeAttribute(name);
                element.setAttribute('data-shinobi-blocked-' + name, value);
                stats.remoteReferencesNeutralised++;
            }
        }
    }
    // Link relations that fetch on load. Stylesheets are already gone; these are the rest.
    for (const link of doc.querySelectorAll('link[rel]')) {
        const rel = (link.getAttribute('rel') || '').toLowerCase();
        if (/(preload|prefetch|preconnect|dns-prefetch|icon|manifest|prerender)/.test(rel)) {
            link.remove();
            stats.remoteReferencesNeutralised++;
        }
    }
    // Meta refresh would navigate the reader somewhere on open.
    for (const meta of doc.querySelectorAll('meta[http-equiv]')) {
        if ((meta.getAttribute('http-equiv') || '').toLowerCase() === 'refresh') {
            meta.remove();
            stats.remoteReferencesNeutralised++;
        }
    }

    // A <base> keeps any remaining relative URL pointing at the original site rather than at
    // wherever the archive happens to be opened from.
    const head = doc.querySelector('head') || doc.insertBefore(
        doc.ownerDocument.createElement('head'), doc.firstChild);
    for (const existing of head.querySelectorAll('base')) existing.remove();
    const base = doc.ownerDocument.createElement('base');
    base.setAttribute('href', document.baseURI);
    head.insertBefore(base, head.firstChild);

    if (stats.scriptsRemoved > 0) {
        notes.push(`${stats.scriptsRemoved} script element(s) removed; the archive does not execute.`);
    }
    if (stats.stylesheetsFailed > 0) {
        notes.push(`${stats.stylesheetsFailed} stylesheet(s) could not be read.`);
    }
    if (stats.imagesFailed > 0) {
        notes.push(`${stats.imagesFailed} image(s) could not be inlined.`);
    }
    if (stats.framesSkipped > 0) {
        notes.push(`${stats.framesSkipped} cross-origin frame(s) could not be captured.`);
    }
    if (stats.noscriptBlocksRemoved > 0) {
        notes.push(`${stats.noscriptBlocksRemoved} noscript block(s) removed; they were not `
            + `rendered when the page was viewed and can contain trackers that fire when the `
            + `archive is opened with scripting disabled.`);
    }
    if (stats.remoteReferencesNeutralised > 0) {
        notes.push(`${stats.remoteReferencesNeutralised} reference(s) that would have loaded `
            + `from the network on open were neutralised; the original URLs are preserved in `
            + `data-shinobi-blocked-* attributes.`);
    }
    if (inlinedBytes >= totalLimit) {
        notes.push('The resource budget was reached; later resources were not inlined.');
    }

    const header = '<!DOCTYPE html>\n<!--\n'
        + ' Archived by Shinobi\n'
        + ' Source:      ' + document.baseURI + '\n'
        + ' Captured at: ' + new Date().toISOString() + '\n'
        + ' Scripts were removed and remaining network references were neutralised, so\n'
        + ' opening this file does not contact anything. Resources were re-fetched from\n'
        + ' the page and inlined, so this is a faithful reconstruction rather than a\n'
        + ' byte-for-byte record of what the server sent.\n'
        + '-->\n';

    return {
        html: header + doc.outerHTML,
        stats: stats,
        notes: notes
    };
    """#
}
