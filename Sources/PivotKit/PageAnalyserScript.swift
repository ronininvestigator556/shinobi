// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

/// The in-page script behind link harvesting and technology fingerprinting.
///
/// Runs in the page for the usual reason — the header request it makes goes out over the
/// container's proxy rather than the machine's own connection — and because the things worth
/// detecting live in the DOM and in JavaScript globals, neither of which is visible from the
/// host.
///
/// **On headers.** `WKWebView` gives no way to see the response that produced the page, so the
/// script re-requests its own URL and reads the headers off that. Two honest limits follow:
/// the request is a second one, so a server that varies its response will not necessarily
/// answer identically, and the browser withholds `Set-Cookie` and other forbidden header names
/// regardless. What is reported is what could actually be read.
public enum PageAnalyserScript {

    public static let source = #"""
    const origin = location.hostname;
    const seenLinks = new Set();
    const links = [];
    const emails = new Set();
    const images = new Set();
    const externalHosts = new Set();

    // ---- Links, addresses and images ---------------------------------------------------

    for (const anchor of document.querySelectorAll('a[href]')) {
        const href = anchor.href;
        if (!href) continue;

        if (href.startsWith('mailto:')) {
            const address = href.slice(7).split('?')[0].trim();
            if (address) emails.add(address.toLowerCase());
            continue;
        }
        if (!/^https?:/i.test(href)) continue;
        if (seenLinks.has(href)) continue;
        if (links.length >= maxLinks) continue;

        seenLinks.add(href);
        let host = '';
        try { host = new URL(href).hostname; } catch (_) { continue; }
        const external = host !== origin;
        if (external) externalHosts.add(host);

        links.push({
            url: href,
            text: (anchor.textContent || '').replace(/\s+/g, ' ').trim().slice(0, 200),
            host: host,
            external: external
        });
    }

    // Addresses written as text rather than linked. Uses innerText so that markup split
    // across elements does not fabricate an address that is not really there.
    const bodyText = document.body ? (document.body.innerText || '') : '';
    for (const match of bodyText.matchAll(/[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,63}/g)) {
        emails.add(match[0].toLowerCase());
        if (emails.size >= maxEmails) break;
    }

    for (const image of document.images) {
        const source = image.currentSrc || image.src;
        if (!source || images.size >= maxImages) continue;
        images.add(source);
        try {
            const host = new URL(source).hostname;
            if (host && host !== origin) externalHosts.add(host);
        } catch (_) { /* data: and blob: have no host */ }
    }

    for (const element of document.querySelectorAll('script[src], link[href], iframe[src]')) {
        const value = element.src || element.href;
        if (!value) continue;
        try {
            const host = new URL(value, document.baseURI).hostname;
            if (host && host !== origin) externalHosts.add(host);
        } catch (_) { /* ignore */ }
    }

    // ---- Technology fingerprinting ------------------------------------------------------

    const html = document.documentElement.outerHTML.slice(0, 400000);
    const scriptSources = Array.from(document.querySelectorAll('script[src]'))
        .map((s) => s.src).join(' ');
    const metaGenerator = (document.querySelector('meta[name="generator" i]') || {}).content || '';
    const cookies = document.cookie || '';

    const found = [];
    const note = (name, category, evidence) => {
        if (!found.some((entry) => entry.name === name)) {
            found.push({ name, category, evidence });
        }
    };

    // Each rule states what it looked at, so the evidence can be shown alongside the claim.
    const rules = [
        // Content management
        ['WordPress', 'CMS', () => /wp-content|wp-includes/i.test(html) && 'wp-content path'],
        ['Drupal', 'CMS', () => /drupal\.js|sites\/default\/files/i.test(html) && 'Drupal path'],
        ['Joomla', 'CMS', () => /\/media\/jui\/|joomla/i.test(html) && 'Joomla path'],
        ['Ghost', 'CMS', () => /ghost-sdk|content\/themes/i.test(html) && 'Ghost asset path'],
        ['MediaWiki', 'CMS', () => (typeof window.mw !== 'undefined') && 'window.mw'],
        ['Squarespace', 'CMS', () => /squarespace/i.test(html) && 'Squarespace asset'],
        ['Wix', 'CMS', () => /wix\.com|wixstatic/i.test(html) && 'Wix asset'],
        ['Webflow', 'CMS', () => /webflow/i.test(html) && 'Webflow asset'],

        // Commerce
        ['Shopify', 'Commerce', () => (typeof window.Shopify !== 'undefined') && 'window.Shopify'],
        ['WooCommerce', 'Commerce', () => /woocommerce/i.test(html) && 'WooCommerce asset'],
        ['Magento', 'Commerce', () => /\/static\/version|magento/i.test(html) && 'Magento path'],

        // Frameworks
        ['React', 'Framework', () => (document.querySelector('[data-reactroot], #__next') ||
            typeof window.React !== 'undefined') && 'React root or global'],
        ['Next.js', 'Framework', () => (document.querySelector('#__next') ||
            typeof window.__NEXT_DATA__ !== 'undefined') && '__NEXT_DATA__'],
        ['Vue', 'Framework', () => (document.querySelector('[data-v-app], #__nuxt') ||
            typeof window.Vue !== 'undefined') && 'Vue root or global'],
        ['Angular', 'Framework', () => (document.querySelector('[ng-version]')) &&
            'ng-version attribute'],
        ['Svelte', 'Framework', () => /svelte-[a-z0-9]{6}/i.test(html) && 'Svelte class hash'],
        ['jQuery', 'Framework', () => (typeof window.jQuery !== 'undefined') &&
            ('jQuery ' + (window.jQuery.fn && window.jQuery.fn.jquery ? window.jQuery.fn.jquery : ''))],
        ['Bootstrap', 'Framework', () => /bootstrap(\.min)?\.(css|js)/i.test(html) && 'Bootstrap asset'],
        ['Tailwind CSS', 'Framework', () => /tailwind/i.test(html) && 'Tailwind asset'],

        // Analytics and tags
        ['Google Analytics', 'Analytics', () => /google-analytics\.com|gtag\/js|googletagmanager/i
            .test(scriptSources + html) && 'Google tag script'],
        ['Matomo', 'Analytics', () => /matomo|piwik/i.test(scriptSources + html) && 'Matomo script'],
        ['Plausible', 'Analytics', () => /plausible\.io/i.test(scriptSources) && 'Plausible script'],
        ['Hotjar', 'Analytics', () => /hotjar/i.test(scriptSources + html) && 'Hotjar script'],
        ['Meta Pixel', 'Analytics', () => /connect\.facebook\.net|fbevents\.js/i
            .test(scriptSources + html) && 'Meta pixel script'],

        // Infrastructure
        ['Cloudflare', 'Infrastructure', () => /cdn-cgi\/|cloudflare/i.test(html) && 'cdn-cgi path'],
        ['Akamai', 'Infrastructure', () => /akamai(hd|ized)?\.net/i.test(html) && 'Akamai host'],
        ['Fastly', 'Infrastructure', () => /fastly(\.net|lb)/i.test(html) && 'Fastly host'],
        ['Amazon CloudFront', 'Infrastructure', () => /cloudfront\.net/i.test(html) && 'CloudFront host'],
        ['jsDelivr', 'Infrastructure', () => /cdn\.jsdelivr\.net/i.test(scriptSources) && 'jsDelivr host'],

        // Protection
        ['reCAPTCHA', 'Protection', () => /recaptcha/i.test(html) && 'reCAPTCHA script'],
        ['hCaptcha', 'Protection', () => /hcaptcha/i.test(html) && 'hCaptcha script'],
    ];

    for (const [name, category, test] of rules) {
        try {
            const evidence = test();
            if (evidence) note(name, category, String(evidence));
        } catch (_) { /* a rule must never break the analysis */ }
    }

    if (metaGenerator) note(metaGenerator.split(' ')[0], 'Declared', 'meta generator: ' + metaGenerator);
    for (const [name, pattern] of [['PHP', /PHPSESSID/], ['ASP.NET', /ASP\.NET_SessionId/],
                                   ['Java', /JSESSIONID/], ['Laravel', /laravel_session/]]) {
        if (pattern.test(cookies)) note(name, 'Platform', 'session cookie');
    }

    // ---- Response headers ---------------------------------------------------------------

    let headers = {};
    try {
        const response = await fetch(location.href, { method: 'HEAD', credentials: 'omit' });
        const interesting = ['server', 'x-powered-by', 'via', 'x-generator', 'content-type',
                             'strict-transport-security', 'content-security-policy',
                             'x-frame-options', 'cf-ray', 'x-cache', 'x-served-by'];
        for (const name of interesting) {
            const value = response.headers.get(name);
            if (value) headers[name] = value.slice(0, 300);
        }
        if (headers['server']) note(headers['server'].split('/')[0], 'Server', 'Server header');
        if (headers['x-powered-by']) note(headers['x-powered-by'].split('/')[0], 'Platform', 'X-Powered-By header');
        if (headers['cf-ray']) note('Cloudflare', 'Infrastructure', 'cf-ray header');
    } catch (_) {
        // A HEAD request the server refuses, or a CSP that blocks it, is ordinary. The
        // absence of headers is reported rather than treated as a failure of the whole scan.
    }

    return {
        pageURL: location.href,
        links: links,
        emails: Array.from(emails),
        images: Array.from(images),
        externalHosts: Array.from(externalHosts),
        technologies: found,
        headers: headers
    };
    """#
}
