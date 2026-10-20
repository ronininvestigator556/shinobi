# Shinobi v1 — Implementation Roadmap

**Spec:** [docs/spec/shinobi-v1.md](../../spec/shinobi-v1.md)

Shinobi spans several independent subsystems, so per the writing-plans scope rule it is built as a sequence of phases. Each phase is its own detailed TDD plan (in this directory) and produces working, testable software on its own. This file is the index and sequencing; it is not itself a task-by-task plan.

## Phases

Each phase links to its detailed plan once written.

- **Phase 1 — Repo bootstrap + kit vendoring.** Fresh GPLv3 repo wired to the remote; SwiftPM/Xcode app scaffold that builds and launches an empty window; vendor the proven kits (`CaseKit`, `ContainerKit`→`IdentityKit`, `CaptureKit`, `PivotKit`, `MonitorKit`), add GPLv3 headers, strip agency-specific config, get everything compiling with the prior tests passing. *Deliverable:* `shinobi` builds, launches, and the vendored kits' unit tests are green.
- **Phase 2 — Identity + Egress.** `IdentityKit` wired to a per-Identity `WKWebsiteDataStore`; BYO proxy from Keychain; explicit labeled `Direct`; egress verification that **fails closed** on every switch. *Deliverable:* create an Identity, open a tab, confirm traffic exits via the chosen egress (and is blocked when a configured proxy drops).
- **Phase 3 — Case + auto-capture.** `CaseKit` writing `.shinobicase`; `CaptureKit` auto-capturing every visit (archive/screenshot/text/metadata) into the content-addressed blob store; custody log; pause + per-Identity toggle. *Deliverable:* browsing in an open Case populates a verifiable bundle.
- **Phase 4 — Format interop + export.** Read existing `.nigelcase`; signed + timestamped export with WARC 1.1; update the `osint-workup` skill to accept both extensions. *Deliverable:* open a prior case, produce a sealed export verifiable with stock tools.
- **Phase 5 — Safari-like UX shell (delta a).** Light+dark chrome, tabs, address bar, Identity strip, capture ledger sidebar.
- **Phase 6 — Blocking + anti-fingerprint (delta c).** Local filtering proxy + uBlock-style filter lists; cookie/consent auto-reject; per-Identity fingerprint persona (UA + canvas/WebGL seed via injected JS).
- **Phase 7 — Pivots + launchers (delta b).** Right-click Indicator pivots opening in-tab through the active Identity; Shodan/VirusTotal/reverse-image/archive; context-search.
- **Phase 8 — Distribution hardening (delta d).** README + build docs, final agency-config strip, source-only release, polish.

## Dependency notes

- Phases 2–4 are the evidentiary core and are strictly ordered (Identity → Case/capture → interop/export).
- Phases 5–7 depend on 2–4 but are largely independent of one another and could be parallelized.
- Phase 8 is last.

## Status

- Phase 1 plan: **pending** — being grounded in a read of the prior repo's exact module layout and public APIs.
