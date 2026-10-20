# Distribution: source-only (build in Xcode) for v1

Shinobi v1 ships as **source only** — users clone the GPLv3 repo and build it in Xcode. No notarized, Developer-ID-signed release, because that requires a paid Apple Developer account the project doesn't have yet.

This is in tension with the "turn-key" goal (a non-technical colleague can't double-click-install), and that tension is accepted for v1: the turn-key promise is about *tools being built in, not extensions to manage* — not about install friction. Notarized `.dmg` releases are the first thing to add once an Apple Developer ID is available.
