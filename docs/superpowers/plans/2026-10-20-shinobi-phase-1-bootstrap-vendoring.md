# Shinobi Phase 1 — Bootstrap & Kit Vendoring — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stand up the `shinobi` repo as a green, buildable SwiftPM project by vendoring the prior tool's proven kits, renamed to Shinobi/Identity vocabulary and isolated from the installed prior app, with every vendored test passing and the app launching an empty window.

**Architecture:** Fresh GPLv3 SwiftPM package reusing the prior tool's module graph verbatim in structure, with a systematic identifier rename (`Nigel`→`Shinobi`, `Container`→`Identity`) applied as each module is vendored. The existing test suites travel with their modules and are the correctness gate — this is a **port-and-verify** phase, not a feature phase, so tasks do not "write a failing test first"; they vendor code + its tests and prove the suite still passes after rename.

**Tech Stack:** Swift 6.2 (language mode v6), SwiftPM (no Xcode project), AppKit + WebKit, GRDB 7.x (CaseKit only), swift-testing (`import Testing`). macOS 26, Apple Silicon.

**Spec:** [docs/spec/shinobi-v1.md](../../spec/shinobi-v1.md) · **Roadmap:** [2026-10-20-shinobi-roadmap.md](./2026-10-20-shinobi-roadmap.md)

## Global Constraints

- **Vendor source:** copy from the prior repo `/Users/thomasallen/Dev/nigel` at a clean stable ref — **use its `main` branch, NOT the in-progress `ios-port-foundation` branch** (confirm the ref before Task 1).
- **Platform:** `.macOS(.v26)`, `.iOS(.v26)` for libraries; the app target is macOS-only. Apple Silicon.
- **Toolchain:** `swift-tools-version: 6.2`; every target `.swiftLanguageMode(.v6)`.
- **Dependencies:** exactly one third-party — GRDB `https://github.com/groue/GRDB.swift.git` `from: "7.0.0"`; copy the prior `Package.resolved` so it pins `7.11.1`. GRDB is linked **only** by CaseKit.
- **License:** GPLv3. Every vendored/new Swift file gets an SPDX header: `// SPDX-License-Identifier: GPL-3.0-or-later` as line 1.
- **Isolation (hard requirement):** Shinobi must not share runtime state with the installed prior app. All of `com.nigel.browser*` identifiers, the `Nigel` Application Support directory, and keychain services must become `com.shinobi.browser*` / `Shinobi` **before the app is run** (Task 9 gate).
- **Deferred to later phases (do NOT change in Phase 1):** the case bundle extension stays `nigelcase` (format interop is Phase 4); real icon artwork (keep a renamed placeholder iconset); any new features.
- **Rename map:** the exact identifier substitutions are in [Appendix A](#appendix-a--rename-map). "Apply the rename map" in a task means: apply every Appendix A row that appears in that task's files.

## Review Focus

Phase-1 risks the vendored tests don't themselves catch, most likely first:

1. **Residual `nigel` identifier pointing at the installed app's data** — a missed keychain service, App Support path, or bundle-id string would make Shinobi silently read/write Nigel's live cases/credentials. Covered by Task 9's `grep -ri nigel` gate (must return zero outside intentional spots).
2. **WebKit script-message name mismatch after rename** — `nigelContextTarget`→`shinobiContextTarget` must change in BOTH the native handler (`ContextTarget.swift`) and the injected JS string, or pivots break at runtime with no compile error. Covered by Task 2 (ContextTarget/ContextScriptInstaller tests) + a grep for the literal.
3. **`WKWebsiteDataStore(forIdentifier:)` reserved-UUID validation preserved** — `WebSessionIdentifier.validate` must still run before the data-store call, or a bad id crashes with an uncatchable ObjC exception. Covered by Task 3 Isolation tests.
4. **GRDB resolution drift** — not copying `Package.resolved` could resolve a newer GRDB with migration-breaking changes. Covered by Task 7 (CaseStore migration tests) + pinning in Task 1.
5. **App Support directory creation race / wrong path** — the four stores (`IdentityStore`, `WatchStore`, `BookmarkStore`, `FilterListStore`) must all point at the new `Shinobi` dir. Covered by Task 3/5/6 store tests exercising `defaultFileURL()`.

---

### Task 1: Repo bootstrap + `ShinobiKit` (ex-`NigelKit`)

**Files:**
- Create: `LICENSE` (GPLv3 full text), `.gitignore` (Swift: `.build/`, `.swiftpm/xcode`, `*.xcuserstate`), `README.md` (skeleton: name, one-line purpose, build/test commands, GPLv3 notice)
- Create: `Package.swift` (declares the package `shinobi` and the `ShinobiKit` library target + `ShinobiKitTests` test target; further targets are added by later tasks)
- Create: `Sources/ShinobiKit/**` ← copy of `Sources/NigelKit/**` (`Coding/Coding.swift`, `Design/InlineActionButton.swift`, `Design/Palette.swift`, `Design/PlatformTypes.swift`, `Design/Typography.swift`, `Web/URLResolver.swift`)
- Create: `Tests/ShinobiKitTests/URLResolverTests.swift` ← ported from the prior `Tests/NigelTests` URLResolver test
- Create: `Package.resolved` ← copy from prior repo (GRDB 7.11.1)

**Interfaces:**
- Produces: `ShinobiKit` module exposing `Palette` (+ `IdentityColor`, ex-`ContainerColor`), `Typography`, `PlatformTypes` (`PlatformColor`/`PlatformFont`), `InlineActionButton.inlineActionStyle()`, `URLResolver.resolve(_:) -> URL?`, and the coding helpers `JSONEncoder.shinobi(prettyPrinted:)`, `JSONDecoder.shinobi()`, `Date.ISO8601FormatStyle.shinobiTimestamp`, `Date.roundedToPersistedPrecision()`. Every later task consumes these names.

- [ ] **Step 1: Initialize repo.** `git init`, `git remote add origin https://github.com/ronininvestigator556/shinobi.git`, create branch `phase-1-vendoring`. The working tree already contains `docs/`, `GLOSSARY.md` from the design session — include them in the initial commit.
- [ ] **Step 2: Write `LICENSE`, `.gitignore`, `README.md` skeleton, and `Package.swift`** declaring package `shinobi`, product/target `ShinobiKit`, and `ShinobiKitTests`, with `swift-tools-version: 6.2` and `.swiftLanguageMode(.v6)`. Copy prior `Package.resolved`.
- [ ] **Step 3: Vendor `Sources/NigelKit/**` → `Sources/ShinobiKit/**`**, apply the rename map (Appendix A), and prepend the SPDX header to each file. Rename `ContainerColor`→`IdentityColor` here (it lives in `Palette.swift`).
- [ ] **Step 4: Port the URLResolver test** into `Tests/ShinobiKitTests/URLResolverTests.swift` (swift-testing style), renamed.
- [ ] **Step 5: Verify.** Run `swift test --filter ShinobiKitTests`. Expected: PASS (URLResolver suite green). Also `swift build` compiles `ShinobiKit`.
- [ ] **Step 6: Commit.** `git add -A && git commit` — "chore: bootstrap shinobi repo and vendor ShinobiKit".

---

### Task 2: `PivotKit` (standalone)

**Files:**
- Create: `Sources/PivotKit/**` ← copy of prior `Sources/PivotKit/**` (13 files incl. `ContextTarget.swift`, `ContextScriptInstaller.swift`, `EntityDetector.swift`, `PivotSource.swift`, `ImageMetadata.swift`, `TextRecognition.swift`, `ArchiveLookup.swift`, `ReverseImageSearch.swift`, `PageAnalysis.swift`/`PageAnalyserScript.swift`, `PageSummariser.swift`, `NamedEntities.swift`, `Entity.swift`)
- Create: `Tests/PivotKitTests/**` ← copy of prior 7 test files (AI, ContextScriptInstaller, ContextTarget, EntityDetector, ImageMetadata, PageAnalysis, PivotSource)
- Modify: `Package.swift` — add `PivotKit` + `PivotKitTests` targets (no internal deps)

**Interfaces:**
- Produces: `Entity`, `EntityDetector`, `PivotSource`/`PivotRegistry`, `NamedEntities`, `ImageMetadata`, `TextRecognition`, `ArchiveLookup`, `ReverseImageSearch`, `PageAnalysis`, `PageSummariser`, `ContextTarget` (message name now `shinobiContextTarget`), `ContextScriptInstaller`.

- [ ] **Step 1: Vendor sources + tests**, apply the rename map, add SPDX headers. Critical: change the WK message name `nigelContextTarget`→`shinobiContextTarget` in `ContextTarget.swift:32` **and** inside the `ContextTarget.script` JS literal; change `nigel-transcribe`→`shinobi-transcribe`.
- [ ] **Step 2: Add the `PivotKit`/`PivotKitTests` targets** to `Package.swift`.
- [ ] **Step 3: Verify.** `swift test --filter PivotKitTests`. Expected: PASS (7 suites). Then `grep -rn "nigelContextTarget\|nigel-transcribe" Sources/PivotKit` → expected: zero hits.
- [ ] **Step 4: Commit** — "feat: vendor PivotKit with shinobi context-bridge names".

---

### Task 3: `IdentityKit` (ex-`ContainerKit`) — the core rename

**Files:**
- Create: `Sources/IdentityKit/**` ← copy of prior `Sources/ContainerKit/**` (`Container.swift`, `ContainerSession.swift`, `ContainerStore.swift`, `EgressChecker.swift`, `ProxyCredentialStore.swift`, `ProxySpec.swift`, `SecurityPolicy.swift`, `WebSessionIdentifier.swift`, `ContentBlocking/{AdblockFilterConverter,ContentBlockerCompiler,ContentRule,FilterListStore}.swift`) — rename the type-named files (`Container.swift`→`Identity.swift`, `ContainerSession.swift`→`IdentitySession.swift`, `ContainerStore.swift`→`IdentityStore.swift`)
- Create: `Tests/IdentityKitTests/**` ← copy of prior `Tests/ContainerKitTests/**` (6 files: AdblockFilterConverter, ContainerStore→IdentityStore, EgressChecker, Isolation, RealFilterList, SecurityPolicy)
- Modify: `Package.swift` — add `IdentityKit` (dep `ShinobiKit`) + `IdentityKitTests`

**Interfaces:**
- Consumes: `ShinobiKit` (`IdentityColor`, coding helpers).
- Produces: `Identity` (ex-`Container`: `struct Identity: Identifiable, Codable, Sendable, Equatable` with `id/name/color/proxy/userAgent/timezone/blocking/security/createdAt`, `static let personal`, `var isPersonal`), `UserAgentProfile`, `BlockingLevel`, `IdentitySessionProvider` (ex-`ContainerSessionProvider`: `configuration(for: Identity) throws -> WKWebViewConfiguration`, `refreshProxy(for:)`, `destroySession(for:) async`, `setRuleList(_:for:)`, `refreshBlocking(for:)`, `SessionError` with `.missingProxyCredential(identity:)`/`.invalidProxy(identity:detail:)`), `IdentityStore` (ex-`ContainerStore`), `ProxySpec`, `ProxyCredentialStore` (keychain `com.shinobi.browser.proxy`), `EgressChecker` (`check(identity:password:) async -> EgressStatus`; `EgressStatus` cases `.unknown/.checking/.direct/.proxied/.leaking/.unproxied/.failed`), `SecurityPolicy`, `WebSessionIdentifier.validate(_:)`, content-blocking types.

- [ ] **Step 1: Vendor sources + tests**, apply the rename map. This is the largest rename: `Container`→`Identity` everywhere (type, params, labels, `SessionError.*(container:)`→`(identity:)`, `EgressChecker.check(container:)`→`(identity:)`), `ContainerSessionProvider`→`IdentitySessionProvider`, `ContainerStore`→`IdentityStore`. Change keychain service `com.nigel.browser.proxy`→`com.shinobi.browser.proxy` (`ProxyCredentialStore.swift:13`), App Support dir `Nigel`→`Shinobi` (`ContainerStore.swift:34`, `ContentBlocking/FilterListStore.swift:41` `"Shinobi/FilterLists"`), dispatch label `com.nigel.browser.container-store`→`com.shinobi.browser.identity-store`. Add SPDX headers. **Leave** `Container.personal`'s fixed UUID `4BB214AB-…` and `ProxySpec.tor` unchanged (Tor preset is harmless dead data until Phase 8 removal).
- [ ] **Step 2: Add the `IdentityKit`/`IdentityKitTests` targets** to `Package.swift`.
- [ ] **Step 3: Verify.** `swift test --filter IdentityKitTests`. Expected: PASS (all 6 suites, incl. EgressChecker leak-detection and Isolation reserved-UUID tests). Then `grep -rn "Container\|com.nigel" Sources/IdentityKit Tests/IdentityKitTests` → expected: zero hits.
- [ ] **Step 4: Commit** — "feat: vendor ContainerKit as IdentityKit (Container→Identity, shinobi keychain/appsupport)".

---

### Task 4: `CaptureKit`

**Files:**
- Create: `Sources/CaptureKit/**` ← copy of prior (`PageArchiver.swift`, `PageArchiverScript.swift`, `PageSnapshotter.swift`, `PageTextExtractor.swift`)
- Create: `Tests/CaptureKitTests/**` ← copy of prior (1 file)
- Modify: `Package.swift` — add `CaptureKit` (dep `ShinobiKit`) + `CaptureKitTests`

**Interfaces:**
- Consumes: `ShinobiKit`. Produces: `PageSnapshotter` (`screenshot(of: WKWebView) async throws -> Snapshot`, `pdf(of:) async throws -> Data`), `PageArchiver` (`archive(_: WKWebView) async throws -> Archive`), `PageTextExtractor` (`extract(from: WKWebView) async -> String?`).

- [ ] **Step 1: Vendor sources + tests**, apply the rename map (any `nigel` coding-helper calls → `shinobi`), add SPDX headers.
- [ ] **Step 2: Add targets** to `Package.swift`.
- [ ] **Step 3: Verify.** `swift test --filter CaptureKitTests`. Expected: PASS.
- [ ] **Step 4: Commit** — "feat: vendor CaptureKit".

---

### Task 5: `MonitorKit`

**Files:**
- Create: `Sources/MonitorKit/**` ← copy of prior (`ChangeDetector.swift`, `Watch.swift`)
- Create: `Tests/MonitorKitTests/**` ← copy of prior (1 file)
- Modify: `Package.swift` — add `MonitorKit` (dep `ShinobiKit`) + `MonitorKitTests`

**Interfaces:**
- Consumes: `ShinobiKit`. Produces: `Watch` (field `containerID`→`identityID`), `WatchStore`, `ChangeDetector`.

- [ ] **Step 1: Vendor sources + tests**, apply the rename map: App Support dir `Nigel`→`Shinobi` (`Watch.swift:124`), dispatch label `com.nigel.browser.watch-store`→`com.shinobi.browser.watch-store`, field `containerID`→`identityID`, coding `.nigel`→`.shinobi`. Add SPDX headers.
- [ ] **Step 2: Add targets** to `Package.swift`.
- [ ] **Step 3: Verify.** `swift test --filter MonitorKitTests`. Expected: PASS. `grep -rn "com.nigel\|Nigel" Sources/MonitorKit` → zero.
- [ ] **Step 4: Commit** — "feat: vendor MonitorKit".

---

### Task 6: `BookmarkKit`

**Files:**
- Create: `Sources/BookmarkKit/**` ← copy of prior (`Bookmark.swift`, `BookmarkMatcher.swift`, `BookmarkStore.swift`, `StarterBookmarks.swift`)
- Create: `Tests/BookmarkKitTests/**` ← copy of prior (1 file)
- Modify: `Package.swift` — add `BookmarkKit` (dep `ShinobiKit`) + `BookmarkKitTests`

**Interfaces:**
- Consumes: `ShinobiKit`. Produces: `Bookmark`, `BookmarkMatcher`, `BookmarkStore`, `StarterBookmarks`.

- [ ] **Step 1: Vendor sources + tests**, apply the rename map: App Support `Nigel`→`Shinobi` (`BookmarkStore.swift:29`), dispatch label `com.nigel.browser.bookmark-store`→`com.shinobi.browser.bookmark-store`, `.nigel` coding→`.shinobi`. Review `StarterBookmarks.swift` for any "Nigel"-branded default entries and rebrand/neutralize. Add SPDX headers.
- [ ] **Step 2: Add targets** to `Package.swift`.
- [ ] **Step 3: Verify.** `swift test --filter BookmarkKitTests`. Expected: PASS.
- [ ] **Step 4: Commit** — "feat: vendor BookmarkKit".

---

### Task 7: `CaseKit` (GRDB)

**Files:**
- Create: `Sources/CaseKit/**` ← copy of prior (`Artifact.swift`, `BlobStore.swift`, `CaptureMode.swift`, `CaseBundle.swift`, `CaseExport.swift`, `CaseManifest.swift`, `CaseRecords.swift`, `CaseStore.swift`, `CustodyReport.swift`, `DER.swift`, `DeviceIdentity.swift`, `TimestampClient.swift`, `WARCWriter.swift`)
- Create: `Tests/CaseKitTests/**` ← copy of prior 5 files (CaptureScope, CaseManifest, CaseStore, Export, Timestamp)
- Modify: `Package.swift` — add `CaseKit` (deps `ShinobiKit`, `IdentityKit`, `.product(name: "GRDB", package: "GRDB.swift")`) + `CaseKitTests`

**Interfaces:**
- Consumes: `ShinobiKit`, `IdentityKit` (records store the identity/`containerName`→`identityName`), GRDB.
- Produces: `CaseBundle` (**`fileExtension` stays `"nigelcase"` — do not change in Phase 1**), `CaseStore`, `BlobStore`, `Artifact`(+`Kind`), `Visit`/`Note`/`CustodyEvent`/`CaseInfo`/`SearchHit`, `CaptureMode`, `CaseManifest` (+`KeychainKeyStore` service `com.shinobi.browser.case-signing`), `CaseExport`, `WARCWriter` (warcinfo software `"Shinobi"`), `TimestampClient`, `CustodyReport`, `DeviceIdentity`.

- [ ] **Step 1: Vendor sources + tests**, apply the rename map: keychain `com.nigel.browser.case-signing`→`com.shinobi.browser.case-signing` (`CaseManifest.swift:82`), manifest `tool: "Nigel"`→`"Shinobi"` (`CaseStore.swift:501`), WARC warcinfo software tag → `"Shinobi"`, `.nigel` coding helpers→`.shinobi`, any `containerName`/`containerID` DB column-adjacent identifiers→`identity*` (keep the **on-disk SQLite column names unchanged** to preserve bundle compatibility — rename only Swift-side symbols; verify against `CaseRecords.swift`). Add SPDX headers.
- [ ] **Step 2: Add the `CaseKit`/`CaseKitTests` targets** to `Package.swift` with the GRDB product dependency.
- [ ] **Step 3: Verify.** `swift test --filter CaseKitTests`. Expected: PASS (5 suites incl. CaseStore GRDB migrations, CaseManifest signing, Export, Timestamp). Confirm GRDB resolved at 7.11.1.
- [ ] **Step 4: Commit** — "feat: vendor CaseKit (shinobi signing key, Shinobi tool tag; nigelcase extension retained for Phase 4)".

---

### Task 8: `Shinobi` app shell (ex-`Nigel`)

**Files:**
- Create: `Sources/Shinobi/**` ← copy of prior `Sources/Nigel/**` (App/, Bookmarks/, Cases/, Containers/→Identities/, Monitoring/, Pivots/, Shell/, Web/)
- Create: `Resources/Info.plist`, `Resources/Shinobi.entitlements`, `Resources/Icon/Shinobi.iconset/` ← from prior `Nigel` equivalents
- Create: `Tests/ShinobiTests/**` ← ported from prior `NigelTests` minus the URLResolver test moved in Task 1 (AddressCompletion, AddressFieldTyping)
- Modify: `Package.swift` — add `executableTarget(name: "Shinobi", dependencies: ["ShinobiKit","IdentityKit","CaseKit","CaptureKit","PivotKit","MonitorKit","BookmarkKit"])` + `ShinobiTests`

**Interfaces:**
- Consumes: all seven kits.

- [ ] **Step 1: Vendor sources + tests**, apply the rename map across the shell. Known hotspots: `BrowserWindowController.swift` — window title "Nigel"→"Shinobi" (`:74`), `setFrameAutosaveName("NigelBrowserWindow")`→`"ShinobiBrowserWindow"` (`:82`), toolbar id `"NigelToolbar"`→`"ShinobiToolbar"` (`:330`), `NSToolbarItem.Identifier("nigel.*")`→`"shinobi.*"` (`:1543–1546`), alert text "Nigel did not open the page"→"Shinobi …" (`:1430`), fallback title (`:1524`); `CaseController.swift:46` UserDefaults key `com.nigel.browser.captureMode`→`com.shinobi.browser.captureMode`; `AppDelegate.swift` doc-example paths. Rename dir `Containers/`→`Identities/` and `ContainerEditor`→`IdentityEditor`. Add SPDX headers.
- [ ] **Step 2: Rename bundle identity:** `Info.plist` `CFBundleName`/`CFBundleDisplayName`/`CFBundleExecutable`/`CFBundleIconFile`→`Shinobi`, `CFBundleIdentifier` `com.nigel.browser`→`com.shinobi.browser`; rename the entitlements and iconset files (keep existing icon art as placeholder).
- [ ] **Step 3: Add the `Shinobi` executable + `ShinobiTests` targets** to `Package.swift`.
- [ ] **Step 4: Verify.** `swift test --filter ShinobiTests`. Expected: PASS (AddressCompletion, AddressFieldTyping). `swift build` compiles the whole package.
- [ ] **Step 5: Commit** — "feat: vendor app shell as Shinobi (bundle id com.shinobi.browser)".

---

### Task 9: Build scripts, `.app` assembly, and whole-package green gate

**Files:**
- Create: `Scripts/run.sh`, `Scripts/build-app.sh`, `Scripts/install.sh`, `Scripts/uninstall.sh` ← adapted from prior
- Modify: `README.md` — fill in real build/run/test instructions

**Interfaces:** none (integration task).

- [ ] **Step 1: Adapt the scripts.** `Nigel.app`→`Shinobi.app`, executable path `.build/.../Nigel`→`Shinobi`, signing env `$NIGEL_SIGNING_IDENTITY`→`$SHINOBI_SIGNING_IDENTITY`; `uninstall.sh` to target `~/Library/Application Support/Shinobi`, `~/Library/WebKit/com.shinobi.browser`, `~/Library/Caches/com.shinobi.browser`, `~/Library/Preferences/com.shinobi.browser.plist`, and keychain services `com.shinobi.browser.proxy` / `com.shinobi.browser.case-signing`.
- [ ] **Step 2: Whole-suite gate.** Run `swift test`. Expected: ALL suites PASS (ShinobiKit, PivotKit, IdentityKit, CaptureKit, MonitorKit, BookmarkKit, CaseKit, Shinobi).
- [ ] **Step 3: Rename-completeness gate.** Run `grep -rin "nigel" Sources Tests Scripts Resources README.md`. Expected: **zero hits** (the only legitimate remaining references — e.g. a comment crediting the prior tool — must be deliberate and listed here; target is zero).
- [ ] **Step 4: Launch gate.** Run `./Scripts/run.sh`. Expected: `Shinobi.app` builds, bundles, and launches an empty browser window titled "Shinobi" with no crash. (Egress/case features are later phases.)
- [ ] **Step 5: Commit + push.** Commit the scripts/README, then `git push -u origin phase-1-vendoring`.

---

## Appendix A — Rename map

Apply every row that appears in a task's files.

| Old | New | Kind | Notes |
|-----|-----|------|-------|
| `NigelKit` | `ShinobiKit` | module/product | Task 1 |
| `ContainerKit` | `IdentityKit` | module/product | Task 3 |
| executable `Nigel` | `Shinobi` | target | Task 8 |
| `Container` (type) | `Identity` | type + all params/labels | incl. `SessionError.*(container:)`→`(identity:)`, `check(container:)`→`(identity:)` |
| `ContainerSessionProvider` | `IdentitySessionProvider` | type | |
| `ContainerStore` | `IdentityStore` | type | |
| `ContainerColor` | `IdentityColor` | type | in `Palette.swift` |
| `ContainerEditor` | `IdentityEditor` | type + `Containers/`→`Identities/` dir | app shell |
| `containerID` / `containerName` (Swift) | `identityID` / `identityName` | symbol | **keep SQLite column names as-is** |
| `JSONEncoder.nigel` / `JSONDecoder.nigel` / `nigelTimestamp` | `.shinobi` / `.shinobi` / `shinobiTimestamp` | func | `ShinobiKit/Coding/Coding.swift` + ~40 call sites |
| `com.nigel.browser` | `com.shinobi.browser` | bundle id / prefix | Info.plist + derived paths |
| `com.nigel.browser.proxy` | `com.shinobi.browser.proxy` | keychain service | |
| `com.nigel.browser.case-signing` | `com.shinobi.browser.case-signing` | keychain service | |
| `com.nigel.browser.captureMode` | `com.shinobi.browser.captureMode` | UserDefaults key | |
| `com.nigel.browser.*-store` | `com.shinobi.browser.*-store` | dispatch labels | identity/watch/bookmark |
| App Support `Nigel` | `Shinobi` | directory name | 4 stores |
| `nigelContextTarget` | `shinobiContextTarget` | WK message name | native + JS |
| `nigel-transcribe` | `shinobi-transcribe` | JS fragment id | |
| manifest `tool: "Nigel"` | `"Shinobi"` | data field | + WARC warcinfo software |
| UI/window strings "Nigel" | "Shinobi" | user-facing | |
| `$NIGEL_SIGNING_IDENTITY` | `$SHINOBI_SIGNING_IDENTITY` | script env | |
| **`nigelcase` extension** | **unchanged** | — | **deferred to Phase 4** |

## Self-review notes

- **Spec coverage:** Phase 1 implements spec §3 (foundation: SwiftPM/WKWebView, platform floor, GPLv3, repo) and the vocabulary of §4 (Identity rename); it does *not* implement capture/egress/UX behavior (Phases 2+). No spec requirement for Phase 1 is left without a task.
- **Type consistency:** `Identity`, `IdentitySessionProvider`, `IdentityStore`, `EgressStatus`, `ProxySpec`, `CaseBundle.fileExtension` are used consistently across Interfaces blocks.
- **Proportion:** this plan directs a vendor+rename of existing, already-tested code; it contains no reimplemented bodies — the gate is the existing suites plus two grep gates. Length is in the rename map and verification, not transcribed code.
- **Port-and-verify caveat:** because behavior is pre-existing and pre-tested, tasks verify by running the vendored suite rather than writing new failing tests first; normal TDD resumes in Phase 2.
