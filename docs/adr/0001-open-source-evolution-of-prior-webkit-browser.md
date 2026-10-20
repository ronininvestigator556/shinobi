# Shinobi is a GPLv3 open-source evolution of a prior WebKit OSINT browser

A prior, privately-developed native Swift/WebKit browser already implements the core of what Shinobi needs: isolated investigative identities with per-identity proxy/egress, background capture (HTML/screenshot/PDF/text/OCR), reverse-image / EXIF / archive pivots, page-change watches, content-addressed storage, Ed25519-signed and RFC-3161-timestamped chain-of-custody, and WARC export. Rather than clean-room rebuild or build a divergent product, we chose to **evolve that proven engine into a new, publicly open-source project (Shinobi, GPLv3)** — standing on working code while stripping agency-specific pieces and adding a turn-key, Safari-like experience.

**Precondition:** the prior codebase is the author's to relicense (self-authored, not work-for-hire owned by a third party, no incompatible third-party code). If that fails, the fallback is a clean-room rebuild that shares only the case/WARC format for interoperability.

## Considered Options

- **Clean-room rebuild** sharing only the on-disk format — slower, but necessary if the prior code can't be open-sourced.
- **Divergent product** (e.g. cross-platform, different capture model) — rejected: throws away a working, field-proven foundation for no v1 benefit.
