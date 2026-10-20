# One Identity per investigation, isolated by a per-Identity data store

Each Identity is backed by its own `WKWebsiteDataStore`. Because that data store both **partitions cookies/cache/storage** and **carries its own proxy configuration** (`proxyConfigurations`, macOS 14+), a single mechanism delivers both investigative isolation and per-case network egress. Switching the active Identity switches storage, fingerprint persona, and exit address together, so Case A can never leak into Case B or back to the operator's home IP.

## Consequences

- An Identity is the browser's core organizing unit; tabs belong to the active Identity.
- Egress must be verified on every switch and **fail closed** — never silently fall back to the home connection.
