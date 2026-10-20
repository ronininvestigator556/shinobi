# Shinobi v1 — Specification

**Status:** accepted (design locked 2026-10-20 via a grilling + domain-modeling session)

Shinobi is an open-source, WebKit-native macOS browser for private-investigator OSINT. Operator anonymity, the case file, and a court-defensible evidence-capture pipeline are the product. See [GLOSSARY.md](../../GLOSSARY.md) for canonical vocabulary and [docs/adr/](../adr/) for the decisions behind each choice.

## 1. What it is

An evolution of a prior, field-proven private tool (Swift/WebKit) into a public GPLv3 project — reusing the proven engine, stripping agency-specific pieces, adding a Safari-like turn-key experience. See [ADR-0001](../adr/0001-open-source-evolution-of-prior-webkit-browser.md).

## 2. Non-goals (v1)

- **No Tor / dark web** — clearnet public-data collection only ([ADR-0004](../adr/0004-no-tor.md)).
- **No access-control circumvention** — no bypassing logins/paywalls, no CAPTCHA solving, no scraping behind auth the operator doesn't own. Public, legally accessible data only.
- **No bundled commercial proxy provider** — operators bring their own proxies.
- **No notarized installer** — source-only build ([ADR-0008](../adr/0008-source-only-distribution-v1.md)).
- **Deferred to v2:** entity-extraction dossier, behavioral (Privacy-Badger-style) tracker blocking.

## 3. Foundation

- **Engine:** stock `WKWebView`; blocking via a local filtering proxy the web views route to; anti-fingerprinting via injected JavaScript ([ADR-0002](../adr/0002-wkwebview-not-custom-webkit.md)).
- **Platform floor:** macOS 26, Apple Silicon ([ADR-0007](../adr/0007-macos-26-apple-silicon-floor.md)).
- **License:** GPLv3.
- **Repo:** `github.com/ronininvestigator556/shinobi` (fresh repo, vendored + renamed kits — not a clone of the prior repo).

## 4. Identity model

- One **Identity** per investigation, backed by its own `WKWebsiteDataStore` — partitioning cookies/cache/storage **and** carrying its own proxy configuration ([ADR-0003](../adr/0003-identity-per-investigation-via-data-store.md)).
- Each Identity has: an **Egress** (a specific BYO SOCKS5/HTTP proxy from the Keychain, **or** an explicit, labeled **Direct** connection), a fingerprint persona (UA + canvas/WebGL seed), and its own capture bucket.
- Egress is **verified on every switch and fails closed** — never silently falls back to the operator's home connection. "Direct" is a deliberate choice, distinct from a failed-proxy fallback.
- Switching Identity switches storage, fingerprint, and egress together. Tabs belong to the active Identity.

## 5. Capture & evidence

- **Auto-capture by default:** within an open Case, every visited page is captured (archive HTML + screenshot + rendered text + metadata), with a visible **pause** and a **per-Identity on/off** ([ADR-0005](../adr/0005-auto-capture-by-default.md)).
- Artifacts are content-addressed by SHA-256; the case carries an append-only **custody log**; manifests are Ed25519-signed and optionally RFC-3161-timestamped (inherited from the prior tool).
- **Watches** (page-change monitoring through an Identity) are retained from the prior tool.

## 6. Case format & interoperability

- Reads existing `.nigelcase` bundles; writes new cases as `.shinobicase` with a **byte-identical internal layout** + a "Shinobi" software tag ([ADR-0006](../adr/0006-case-format-read-nigelcase-write-shinobicase.md)).
- **Export** produces a sealed, independently verifiable hand-off (per-artifact files, signed manifest, `SHA256SUMS`, custody, WARC 1.1) using stock-tool-verifiable formats.
- Shinobi writes case bundles/exports under `~/Documents/Casteel Agency/<Case>/`; it **never** writes into the `/Volumes/Casework` vault or mutates a signed export. The `osint-workup` skill remains the bridge to the vault and must be updated to accept both `.nigelcase` and `.shinobicase`.

## 7. v1 feature delta (new vs. the prior tool)

- **(a) Safari-like UX** — light+dark, familiar browser chrome, replacing the prior dark-only AppKit shell.
- **(b) Pivots & launchers** — right-click an **Indicator** (IP/email/username/hash/domain) → open the service (Shodan, VirusTotal, reverse-image, archive) **in a new tab inside the active Identity**; plus context-search (selected text → many engines). No API keys in v1.
- **(c) Blocking upgrade** — uBlock-style filter lists via the local proxy + cookie/consent auto-reject.
- **(d) Open-source hardening** — GPLv3 headers, public README/build docs, strip agency-specific paths/config, remove the Tor code path.

## 8. Defaults

- Default new-tab search engine: **DuckDuckGo**.
