# Ship on stock WKWebView, not a custom WebKit build

Shinobi renders with Apple's stock **WKWebView**, blocks trackers/ads through a **local filtering proxy** that the web views are routed to, and defends against fingerprinting via **injected JavaScript** (canvas/WebGL/navigator overrides keyed to each Identity). We accept that this is injection-grade anti-fingerprinting, not the C++-level resist-fingerprinting that only a custom WebKit build (or Tor Browser) provides.

Building WebKit from source would give deeper control but costs months-to-years of C++ maintenance for a single-operator tool — not justified for v1. This choice also means per-request interception is limited (WKWebView runs networking in a separate process and does not fire `NSURLProtocol`), which is **why** blocking lives in a local proxy rather than in-process request rewriting.
