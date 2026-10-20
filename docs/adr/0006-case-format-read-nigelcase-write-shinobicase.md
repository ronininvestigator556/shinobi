# Case format: read `.nigelcase`, write `.shinobicase`, identical layout

Shinobi treats the prior tool's transparent case-bundle layout as a shared, project-neutral interchange format. It **reads** existing `.nigelcase` bundles so in-flight cases keep opening, and **writes** new cases as `.shinobicase` with a byte-identical internal layout and a "Shinobi" software tag in the manifest/WARC `warcinfo`.

Keeping the on-disk layout identical means examiners, WARC tooling (pywb / replayweb.page / warcio), and the signature/custody verification steps are all unaffected. The distinct extension keeps Shinobi and the prior tool from blurring together, which the author explicitly wanted.

## Consequences

- The `osint-workup` skill must be updated to accept **both** `.nigelcase` and `.shinobicase`.
- `formatVersion` continues to gate readers: an unknown version is refused, not guessed at.
