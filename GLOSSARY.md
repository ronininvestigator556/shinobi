# Shinobi

Shinobi is an open-source, WebKit-native macOS browser for private-investigator OSINT, where operator anonymity, the case file, and a court-defensible evidence-capture pipeline are the product — not an afterthought bolted onto a general browser.

## Language

### Identities & isolation

**Identity**:
An isolated investigative persona you browse as, carrying its own network egress, fingerprint, and storage so one investigation can never bleed into another.
_Avoid_: Container, profile, persona, account

**Egress**:
The route an Identity's traffic takes to the internet — a specific proxy, or an explicit, clearly-labeled **Direct** connection. Never a silent fallback.
_Avoid_: Exit, route, connection

**Indicator**:
An on-page datum worth investigating further — an IP, email, username, hash, or domain.
_Avoid_: Selector, entity, IOC

### Cases & evidence

**Case**:
A single investigation and the bundle that holds everything captured for it.
_Avoid_: Project, matter, folder

**Capture**:
The act of recording a visited page as preserved evidence, and the record it produces.
_Avoid_: Snapshot, grab, save

**Artifact**:
One recorded piece of evidence produced by a capture (rendered text, self-contained archive HTML, screenshot, PDF, or OCR transcription).
_Avoid_: File, asset, item

**Exhibit**:
An artifact selected for inclusion in a court-facing export.
_Avoid_: Evidence item, piece

**Custody log**:
The append-only record of every action that touched a case — who, what, when, and with which signing key.
_Avoid_: Audit trail, history, journal

**Export**:
The sealed, independently verifiable hand-off package built from a case, readable and checkable with stock tools.
_Avoid_: Dump, backup, archive

### Analysis

**Pivot**:
Taking an indicator from a page and querying it against an external service in one step.
_Avoid_: Lookup, enrich

**Watch**:
A page Shinobi re-checks over time, through its Identity, to detect changes.
_Avoid_: Monitor, alert, subscription
