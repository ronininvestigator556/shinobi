# Shinobi

An open-source, WebKit-native macOS browser for private-investigator OSINT. Operator anonymity, the case file, and a court-defensible evidence-capture pipeline are the product — not an afterthought bolted onto a general browser.

> **Status:** early development. Phase 1 (repo bootstrap + kit vendoring) in progress — see [docs/superpowers/plans/](docs/superpowers/plans/).

## What it is

Shinobi partitions each investigation into an isolated **Identity** (its own storage, network egress, and fingerprint), auto-captures visited pages as verifiable evidence, and exports sealed, independently-checkable case bundles. See [docs/spec/shinobi-v1.md](docs/spec/shinobi-v1.md) for the full specification and [docs/adr/](docs/adr/) for the decisions behind it.

## Requirements

- macOS 26, Apple Silicon
- Swift 6.2+ toolchain (Xcode 26)

## Build & run

```bash
swift test            # run the unit test suites
./Scripts/run.sh      # build, bundle, and launch Shinobi.app (added in Phase 1)
```

## License

GPLv3 — see [LICENSE](LICENSE). Copyleft: forks and derivatives stay open.
