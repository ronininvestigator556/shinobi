// SPDX-License-Identifier: GPL-3.0-or-later
import AppKit
import BookmarkKit
import CaptureKit
import CaseKit
import Combine
import IdentityKit
import MonitorKit
import ShinobiKit
import PivotKit
import SwiftUI
import WebKit

/// One browser window: sidebar, tab strip, web content, inspector, identity strip.
@MainActor
final class BrowserWindowController: NSWindowController {

    private let sidebar = SidebarViewController()
    private let content = BrowserContentViewController()
    private let inspector = InspectorViewController()
    private let identityStrip = IdentityStripView()
    private let addressField = AddressField()
    private let navigationControl = NSSegmentedControl()
    private let reloadButton = NSButton()
    private let captureButton = NSButton()

    private let cases = CaseController()
    private var watches: WatchStore!
    private var watchRunner: WatchRunner!
    private var watchObserver: AnyCancellable?
    private var caseObserver: AnyCancellable?

    private var bookmarks: BookmarkStore!
    private let contextInstaller = ContextScriptInstaller()
    private let contextRelay = ContextMessageRelay()

    /// Behavioural tracker blocking: the learner's memory, the message relay that feeds it,
    /// and the set of content controllers already wired for reporting (so a reused controller
    /// is not handed the handler twice — which WebKit answers with an Objective-C exception).
    private let behaviorLearner = BehaviorLearner()
    private let trackerRelay = TrackerReportRelay()
    private var trackerReportingControllers = Set<ObjectIdentifier>()
    private var didApplyLearnedTrackers = false

    private let egressChecker = EgressChecker()
    private var egressStatus: EgressStatus = .unknown
    private var lastEgressFailure: String?

    private let splitViewController = NSSplitViewController()
    private var sidebarItem: NSSplitViewItem?
    private var inspectorItem: NSSplitViewItem?

    private var tabs: [BrowserTab] = []

    /// Global forced-dark-mode preference for page content (view-only), remembered across
    /// launches. New tabs inherit it; captures are unaffected.
    private var readerDarkEnabled = UserDefaults.standard.bool(forKey: "com.shinobi.browser.readerDark")
    private var selectedTabID: UUID?
    private var tabObservers: [UUID: Set<AnyCancellable>] = [:]

    private var identities: IdentityStore!
    private var sessions: IdentitySessionProvider!

    /// The identity new tabs are created in.
    private var activeContainer: Identity = .personal {
        didSet { refreshIdentityStrip() }
    }

    private var selectedTab: BrowserTab? {
        tabs.first { $0.id == selectedTabID }
    }

    // MARK: Construction

    convenience init(
        identities: IdentityStore,
        sessions: IdentitySessionProvider,
        watches: WatchStore,
        bookmarks: BookmarkStore
    ) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1440, height: 900),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Shinobi"
        window.minSize = NSSize(width: 900, height: 560)
        // Appearance follows the system (light or dark); the palette resolves per appearance.
        window.backgroundColor = Palette.windowBackground
        // Deliberately not `fullSizeContentView`: the toolbar and the identity-strip
        // accessory beneath it are chrome that must always be present and never be
        // overlapped by content.
        window.titlebarAppearsTransparent = false
        window.setFrameAutosaveName("ShinobiBrowserWindow")
        // Shinobi has its own tab strip. Leaving AppKit's window tabbing on adds "Show Tab
        // Bar" and "Show All Tabs" to the View menu, which do something entirely different
        // from ⌘T and would stack a second, unrelated tab bar above this one.
        window.tabbingMode = .disallowed

        self.init(window: window)

        self.identities = identities
        self.sessions = sessions
        self.watches = watches
        self.bookmarks = bookmarks
        self.activeContainer = identities.identity(withID: Identity.personal.id) ?? .personal
        self.watchRunner = WatchRunner(store: watches, identities: identities, sessions: sessions)

        setupSplitView()
        setupToolbar()
        setupIdentityStrip()
        wireCallbacks()

        ledgerIdle()
        newTab()
        checkEgress()

        watchObserver = watchRunner.didObserveChange.sink { [weak self] watch, comparison in
            self?.content.ledger.line = "\(watch.name) changed — \(comparison.summary)"
            self?.content.ledger.accent = Palette.statusWarn
        }
        watchRunner.start()
        rebuildBookmarksMenu()
    }

    /// Places the window inside the current screen.
    ///
    /// `setFrameAutosaveName` restores the saved frame when the window is shown, which
    /// happens *after* `init` — so centring during construction is simply overwritten. It
    /// also restores frames that no longer fit: a window saved on a larger display, or
    /// saved before the chrome grew, ends up with its toolbar above the menu bar and its
    /// controls unreachable. Clamping on show handles both.
    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)

        guard let window, let visible = (window.screen ?? NSScreen.main)?.visibleFrame else { return }
        let frame = window.frame
        guard !visible.contains(frame) else { return }

        var corrected = frame
        corrected.size.width = min(corrected.width, visible.width)
        corrected.size.height = min(corrected.height, visible.height)
        corrected.origin.x = min(max(corrected.minX, visible.minX), visible.maxX - corrected.width)
        corrected.origin.y = min(max(corrected.minY, visible.minY), visible.maxY - corrected.height)
        window.setFrame(corrected, display: true)
    }

    private func setupSplitView() {
        let splitViewController = self.splitViewController
        splitViewController.splitView.dividerStyle = .thin

        let sidebarItem = NSSplitViewItem(viewController: sidebar)
        sidebarItem.minimumThickness = 170
        sidebarItem.maximumThickness = 300
        sidebarItem.canCollapse = true
        sidebarItem.holdingPriority = NSLayoutConstraint.Priority(260)
        splitViewController.addSplitViewItem(sidebarItem)
        self.sidebarItem = sidebarItem

        let contentItem = NSSplitViewItem(viewController: content)
        contentItem.minimumThickness = 480
        contentItem.holdingPriority = .defaultLow
        splitViewController.addSplitViewItem(contentItem)

        let inspectorItem = NSSplitViewItem(viewController: inspector)
        inspectorItem.minimumThickness = 230
        inspectorItem.maximumThickness = 380
        inspectorItem.canCollapse = true
        inspectorItem.holdingPriority = NSLayoutConstraint.Priority(261)
        splitViewController.addSplitViewItem(inspectorItem)
        self.inspectorItem = inspectorItem

        // The identity strip lives in the content view, above the split view — never in a
        // titlebar accessory.
        //
        // A titlebar accessory is hidden along with the toolbar when a full-screen window
        // auto-hides its titlebar, which silently removed the one element this interface
        // promises is always present. `fullScreenMinHeight` is documented to keep an
        // accessory visible in exactly that situation and did not. Rather than depend on
        // titlebar semantics for a safety-critical element, the strip is now an ordinary
        // subview that nothing in AppKit can decide to hide.
        let root = NSView()
        root.wantsLayer = true
        root.setLayerBackground(Palette.windowBackground)

        identityStrip.translatesAutoresizingMaskIntoConstraints = false
        splitViewController.view.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(identityStrip)
        root.addSubview(splitViewController.view)

        NSLayoutConstraint.activate([
            identityStrip.topAnchor.constraint(equalTo: root.topAnchor),
            identityStrip.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            identityStrip.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            identityStrip.heightAnchor.constraint(equalToConstant: IdentityStripView.stripHeight),

            splitViewController.view.topAnchor.constraint(equalTo: identityStrip.bottomAnchor),
            splitViewController.view.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            splitViewController.view.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            splitViewController.view.bottomAnchor.constraint(equalTo: root.bottomAnchor),
        ])

        let rootController = NSViewController()
        rootController.view = root
        rootController.addChild(splitViewController)
        window?.contentViewController = rootController
    }

    private func setupIdentityStrip() {
        refreshIdentityStrip()
        identityStrip.capture = .off
    }

    /// Mirrors the active identity into the strip.
    private func refreshIdentityStrip() {
        identityStrip.containerName = activeContainer.name
        identityStrip.containerColor = Palette.color(for: activeContainer.color)

        applyEgress(egressStatus, for: activeContainer)
    }

    /// Translates a checked egress status into what the strip shows.
    private func applyEgress(_ status: EgressStatus, for identity: Identity) {
        let label = identity.proxy?.displayLabel ?? "Direct"

        switch status {
        case .unknown, .checking:
            identityStrip.egress = .pending(label: label)
        case .direct(let address):
            identityStrip.egress = .direct(address: address)
        case .proxied(let address):
            identityStrip.egress = .proxied(label: label, address: address)
        case .leaking(let address):
            identityStrip.egress = .leaking(address: address)
        case .unproxied(let address):
            // A working identity with no proxy browses from the investigator's own address.
            // Legitimate, but a poor default, so the strip says so rather than reporting a
            // neutral "Direct".
            _ = address
            identityStrip.egress = .unproxied
        case .failed(let reason):
            identityStrip.egress = .failed(label: label)
            lastEgressFailure = reason
        }
    }

    // MARK: Content blocking

    /// Reports the outcome of a rule-list compile in the ledger.
    ///
    /// Surfaced rather than silent because the number that matters — how many rules were
    /// dropped as inexpressible — is otherwise invisible, and an investigator comparing
    /// Shinobi's rendering against another browser deserves to know the blocking is not
    /// identical to uBlock Origin's.
    func contentBlockingDidChange(
        _ reports: [ContentBlockerCompiler.Report],
        updatedSources: [FilterListStore.Source] = []
    ) {
        guard let standard = reports.first(where: { $0.level == .standard }) else { return }

        var message = "Blocking \(standard.converted) rules"
        if standard.truncated { message += " (WebKit rule limit reached)" }
        else if standard.skipped > 0 { message += " (\(standard.skipped) not expressible in WebKit)" }
        if !updatedSources.isEmpty {
            message += " · updated " + updatedSources.map(\.displayName).joined(separator: ", ")
        }

        content.ledger.line = message
        content.ledger.accent = Palette.statusCapture

        // Return to whatever the ledger should actually be showing, rather than leaving a
        // stale rule count sitting there. Restoring the *resting* message here was wrong:
        // six seconds after launch it replaced "Recording to Muller" with "No case open —
        // pages are not being preserved" while a case was open and recording. A status line
        // that contradicts the rest of the interface is worse than no status line, and in
        // this direction it tells an investigator their work is not being kept when it is.
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(6))
            self?.refreshCaseChrome()
        }
    }

    func reportFilterListFailure(_ error: Error) {
        content.ledger.line = "Could not update blocking lists — \(error.localizedDescription)"
        content.ledger.accent = Palette.statusWarn
    }

    /// Re-checks where the active identity's traffic actually leaves from.
    ///
    /// Run on every identity switch rather than only on demand: a proxy that has quietly
    /// stopped carrying traffic looks identical to one that is working, and an investigator
    /// who has to remember to press a button will find out too late.
    @objc func checkEgress() {
        let identity = activeContainer
        egressStatus = .checking
        applyEgress(.checking, for: identity)

        Task { [weak self] in
            guard let self else { return }
            let password = identity.proxy?.requiresPassword == true
                ? ProxyCredentialStore.password(forContainer: identity.id)
                : nil
            let status = await self.egressChecker.check(identity: identity, password: password)

            // The user may have switched identities while the check was in flight; a result
            // for a identity we are no longer in must not be shown as if it were current.
            guard self.activeContainer.id == identity.id else { return }
            self.egressStatus = status
            self.applyEgress(status, for: identity)
        }
    }

    // MARK: Toolbar

    private func setupToolbar() {
        navigationControl.segmentCount = 2
        navigationControl.segmentStyle = .separated
        navigationControl.trackingMode = .momentary
        navigationControl.setImage(
            NSImage(systemSymbolName: "chevron.left", accessibilityDescription: "Back"), forSegment: 0
        )
        navigationControl.setImage(
            NSImage(systemSymbolName: "chevron.right", accessibilityDescription: "Forward"), forSegment: 1
        )
        navigationControl.target = self
        navigationControl.action = #selector(navigate)

        reloadButton.isBordered = true
        reloadButton.bezelStyle = .texturedRounded
        reloadButton.image = NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: "Reload")
        reloadButton.target = self
        reloadButton.action = #selector(reloadOrStop)

        captureButton.isBordered = true
        captureButton.bezelStyle = .texturedRounded
        captureButton.image = NSImage(
            systemSymbolName: "camera.viewfinder", accessibilityDescription: "Capture this page")
        captureButton.target = self
        captureButton.action = #selector(captureThisPage)
        captureButton.toolTip = "Capture this page (⇧⌘R)"

        let toolbar = NSToolbar(identifier: "ShinobiToolbar")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
        toolbar.centeredItemIdentifiers = [.address]
        window?.toolbar = toolbar
        window?.toolbarStyle = .unified
    }

    private func wireCallbacks() {
        content.tabBar.onSelect = { [weak self] id in self?.select(id) }
        content.tabBar.onClose = { [weak self] id in self?.closeTab(id) }
        content.tabBar.onNewTab = { [weak self] in self?.newTab() }
        addressField.onSubmit = { [weak self] input in
            self?.handleAddressEntry(input)
        }
        addressField.completionSource = { [weak self] typed in
            guard let self else { return [] }
            return BookmarkMatcher.matches(for: typed, in: self.bookmarks.all)
        }
        // A suggestion opens in the tab in front, the way typing an address does. It does not
        // open a new one — that is what the Bookmarks menu is for.
        addressField.onChooseSuggestion = { [weak self] match in
            guard let self, let url = match.bookmark.resolvedURL() else { return }
            self.bookmarks.recordUse(id: match.bookmark.id)
            self.selectedTab?.load(url)
        }
        content.findBar.onSearch = { [weak self] query, forward in
            self?.performFind(query, forward: forward)
        }
        content.findBar.onDismiss = { [weak self] in self?.hideFindBar() }

        sidebar.onSelectContainer = { [weak self] identity in self?.switchTo(identity) }
        sidebar.onAddContainer = { [weak self] in self?.presentEditor(for: nil) }
        sidebar.onEditContainer = { [weak self] identity in self?.presentEditor(for: identity) }
        sidebar.onDeleteContainer = { [weak self] identity in self?.confirmDelete(identity) }

        identities.onChange = { [weak self] _ in
            MainActor.assumeIsolated { self?.reloadSidebar() }
        }

        caseObserver = cases.didChange.sink { [weak self] in
            self?.reloadSidebar()
            self?.refreshCaseChrome()
        }
        cases.onRecordingFailure = { [weak self] error in
            // A case that stops recording without saying so is the worst failure this
            // subsystem has, so it is reported in the ledger rather than logged.
            self?.content.ledger.line = "Not recording — \(error.localizedDescription)"
            self?.content.ledger.accent = Palette.statusAlert
        }
        reloadSidebar()
    }

    // MARK: Identities

    private func reloadSidebar() {
        sidebar.reload(
            identities: identities.all,
            activeID: activeContainer.id,
            caseName: cases.caseName,
            captureCount: cases.visitCount
        )
    }

    // MARK: Cases

    @objc func newCase() {
        let panel = NSSavePanel()
        panel.title = "New Case"
        panel.prompt = "Create"
        panel.nameFieldStringValue = "Untitled case"
        panel.allowedContentTypes = []
        panel.allowsOtherFileTypes = true

        panel.beginSheetModal(for: window!) { [weak self] response in
            guard response == .OK, var url = panel.url, let self else { return }
            if url.pathExtension != CaseBundle.fileExtension {
                url = url.appendingPathExtension(CaseBundle.fileExtension)
            }
            do {
                try self.cases.create(
                    at: url,
                    name: url.deletingPathExtension().lastPathComponent,
                    reference: nil
                )
                self.recordAlreadyOpenPages()
            } catch {
                self.presentSessionFailure(error)
            }
        }
    }

    @objc func openCase() {
        let panel = NSOpenPanel()
        panel.title = "Open Case"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false

        panel.beginSheetModal(for: window!) { [weak self] response in
            guard response == .OK, let url = panel.url, let self else { return }
            do {
                try self.cases.open(at: url)
                self.recordAlreadyOpenPages()
            } catch {
                self.presentSessionFailure(error)
            }
        }
    }

    /// Opens the case at `url`, creating it if nothing is there.
    func openOrCreateCase(at url: URL) {
        do {
            if FileManager.default.fileExists(atPath: url.path) {
                try cases.open(at: url)
            } else {
                try cases.create(
                    at: url,
                    name: url.deletingPathExtension().lastPathComponent,
                    reference: nil
                )
            }
            recordAlreadyOpenPages()
        } catch {
            presentSessionFailure(error)
        }
    }

    /// Records pages that were already loaded when the case was opened.
    ///
    /// Without this, an investigator who browses to something and *then* opens a case finds
    /// the page they were looking at is not in it — and finds out only later, if at all.
    /// Recording an unwanted page is a visible, explainable mistake; silently omitting one
    /// the investigator believes is recorded is the failure this tool exists to prevent.
    /// Every visit carries the identity it was viewed in, so nothing here is untraceable.
    private func recordAlreadyOpenPages() {
        for tab in tabs where tab.url != nil && !tab.isLoading {
            cases.record(tab)
        }
    }

    @objc func closeCase() {
        cases.close()
    }

    @objc func searchCase() {
        guard cases.isOpen, let window, let name = cases.caseName else {
            NSSound.beep()
            return
        }

        var sheet: NSWindow?
        let view = CaseSearchView(
            caseName: name,
            search: { [weak self] query in self?.cases.search(query) ?? [] },
            onOpen: { [weak self] url in
                sheet.map { window.endSheet($0) }
                self?.open(url)
            },
            onClose: { sheet.map { window.endSheet($0) } }
        )

        let hosting = NSHostingController(rootView: view)
        let sheetWindow = NSWindow(contentViewController: hosting)
        sheet = sheetWindow
        window.beginSheet(sheetWindow)
    }

    /// Exports without any interface, for the command-line path. Named distinctly from the
    /// menu action so the two cannot be confused at a call site.
    @discardableResult
    func exportCaseWithoutUI(to destination: URL) throws -> CaseExport.Summary {
        try cases.export(to: destination)
    }

    @objc func exportCase() {
        guard cases.isOpen, let window else {
            NSSound.beep()
            return
        }

        let panel = NSSavePanel()
        panel.title = "Export Case"
        panel.prompt = "Export"
        panel.nameFieldStringValue = (cases.caseName ?? "Case") + " export"
        panel.message = "A folder anyone can verify with shasum and openssl, without Shinobi."

        let scope = NSButton(checkboxWithTitle: "Only pages with captured exhibits", target: nil, action: nil)
        scope.state = cases.captureMode == .continuous ? .off : .on
        scope.toolTip = "Leaves out pages that were logged but never captured. The export "
            + "says how many were omitted."
        scope.sizeToFit()
        panel.accessoryView = scope

        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url, let self else { return }
            do {
                let summary = try self.cases.export(to: url, exhibitsOnly: scope.state == .on)
                let alert = NSAlert()
                alert.messageText = "Case exported"
                alert.informativeText = "\(summary.artifactCount) artifact(s) from "
                    + "\(summary.visitCount) page(s), "
                    + ByteCountFormatter.string(fromByteCount: Int64(summary.byteCount), countStyle: .file)
                    + ".\n\nREADME.txt in the folder explains how to verify it and what the "
                    + "signature does and does not establish."
                alert.addButton(withTitle: "Reveal in Finder")
                alert.addButton(withTitle: "Done")
                alert.beginSheetModal(for: window) { choice in
                    if choice == .alertFirstButtonReturn {
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    }
                }
            } catch {
                self.presentSessionFailure(error)
            }
        }
    }

    // MARK: Pivots

    /// Opens a lookup in a new tab bound to the same identity as the page it came from.
    private func openPivot(_ url: URL, from source: BrowserTab) {
        guard let tab = createTab(in: source.identity) else { return }
        tab.load(url)
    }

    /// Fetches an image through its own identity and shows what is embedded in it.
    private func inspectImage(_ url: URL, in tab: BrowserTab) {
        guard let window else { return }

        Task { [weak self] in
            guard let self else { return }
            do {
                let session = URLSession(configuration: self.imageSessionConfiguration(for: tab))
                defer { session.invalidateAndCancel() }
                let reading = try await ImageMetadata.read(from: url, using: session)

                let hosting = NSHostingController(rootView: ImageMetadataView(
                    reading: reading,
                    onOpenMap: { [weak self] mapURL in self?.openPivot(mapURL, from: tab) },
                    onClose: { [weak self] in
                        self?.window?.sheets.first.map { self?.window?.endSheet($0) }
                    }
                ))
                await window.beginSheet(NSWindow(contentViewController: hosting))
            } catch {
                let alert = NSAlert()
                alert.messageText = "The image could not be read"
                alert.informativeText = error.localizedDescription
                alert.addButton(withTitle: "OK")
                await alert.beginSheetModal(for: window)
            }
        }
    }

    /// Reads the text out of an image on demand.
    private func transcribeImage(_ url: URL, in tab: BrowserTab) {
        guard let window else { return }

        Task { [weak self] in
            guard let self else { return }
            let session = URLSession(configuration: self.imageSessionConfiguration(for: tab))
            defer { session.invalidateAndCancel() }

            let alert = NSAlert()
            do {
                let (data, _) = try await session.data(from: url)
                let reading = try TextRecognition.recognise(in: data)
                if reading.isEmpty {
                    alert.messageText = "No text found"
                    alert.informativeText = "Nothing in this image was recognised as text."
                } else {
                    alert.messageText = "Transcribed text"
                    // The caveat is part of the message rather than a separate note: a
                    // transcription read confidently and wrongly is the normal failure here.
                    alert.informativeText = reading.text + "\n\n— " + reading.note
                    alert.addButton(withTitle: "Copy")
                }
            } catch {
                alert.messageText = "The image could not be read"
                alert.informativeText = error.localizedDescription
            }
            alert.addButton(withTitle: "Done")

            let choice = await alert.beginSheetModal(for: window)
            if choice == .alertFirstButtonReturn, alert.messageText == "Transcribed text" {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(
                    alert.informativeText.components(separatedBy: "\n\n— ").first ?? "",
                    forType: .string)
            }
        }
    }

    /// A session that exits the same way the tab does.
    private func imageSessionConfiguration(for tab: BrowserTab) -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 20
        if let spec = tab.identity.proxy {
            let password = spec.requiresPassword
                ? ProxyCredentialStore.password(forContainer: tab.identity.id)
                : nil
            if let proxy = spec.makeProxyConfiguration(password: password) {
                configuration.proxyConfigurations = [proxy]
            }
        }
        return configuration
    }

    /// Summarises the current page with the on-device model.
    @objc func summarisePage() {
        guard let tab = selectedTab, let window else {
            NSSound.beep()
            return
        }

        let summariser = PageSummariser()
        guard case .available = summariser.availability() else {
            let alert = NSAlert()
            alert.messageText = "The on-device model is not available"
            if case .unavailable(let reason) = summariser.availability() {
                alert.informativeText = reason
                    + "\n\nEverything else in Shinobi works without it. Entity extraction and "
                    + "transcription do not use this model."
            }
            alert.addButton(withTitle: "OK")
            alert.beginSheetModal(for: window)
            return
        }

        content.ledger.line = "Summarising…"
        content.ledger.accent = Palette.textSecondary

        Task { [weak self] in
            guard let self else { return }
            let text = await PageTextExtractor.extract(from: tab.webView) ?? ""
            do {
                let summary = try await summariser.summarise(text)
                let alert = NSAlert()
                alert.messageText = "Summary"
                // The disclaimer is part of the message, not a footnote elsewhere: this text
                // is machine-written and must never be mistaken for the record.
                alert.informativeText = summary.text + "\n\n— " + summary.disclaimer
                alert.addButton(withTitle: "Copy")
                alert.addButton(withTitle: "Done")
                let choice = await alert.beginSheetModal(for: window)
                if choice == .alertFirstButtonReturn {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(summary.text, forType: .string)
                }
            } catch {
                let alert = NSAlert()
                alert.messageText = "No summary"
                alert.informativeText = error.localizedDescription
                alert.addButton(withTitle: "OK")
                await alert.beginSheetModal(for: window)
            }
            self.refreshCaseChrome()
        }
    }

    /// Extracts named entities from the page and shows them in the inspector.
    private func refreshEntities(for tab: BrowserTab?) {
        guard let tab else {
            inspector.showEntities([])
            return
        }
        Task { [weak self] in
            let text = await PageTextExtractor.extract(from: tab.webView) ?? ""
            guard let self, self.selectedTab === tab else { return }
            self.inspector.showEntities(NamedEntities.extract(from: text, limit: 40))
        }
    }

    /// Harvests the current page and shows what it contains.
    @objc func analysePage() {
        guard let tab = selectedTab, let pageURL = tab.url, let window else {
            NSSound.beep()
            return
        }

        content.ledger.line = "Analysing \(pageURL.host ?? "page")…"
        content.ledger.accent = Palette.textSecondary

        Task { [weak self] in
            guard let self else { return }

            let payload = try? await tab.webView.callAsyncJavaScript(
                PageAnalyserScript.source,
                arguments: ["maxLinks": 2000, "maxEmails": 500, "maxImages": 500],
                contentWorld: .defaultClient
            ) as? [String: Any]
            let analysis = PageAnalysis(payload: payload ?? [:])

            // The archive lookup goes out over the tab's own identity, so checking whether a
            // subject's page is archived does not do so from the investigator's own address.
            let session = URLSession(configuration: self.imageSessionConfiguration(for: tab))
            let archives = await ArchiveLookup().lookUp(pageURL, using: session)
            session.invalidateAndCancel()

            var sheet: NSWindow?
            let view = PageAnalysisView(
                analysis: analysis,
                archives: archives,
                onOpen: { [weak self] url in self?.openPivot(url, from: tab) },
                onSaveToArchive: { [weak self] in
                    sheet.map { window.endSheet($0) }
                    self?.confirmArchiveSubmission(for: pageURL, from: tab)
                },
                onCopy: { text in
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                },
                onClose: { sheet.map { window.endSheet($0) } }
            )

            let hosting = NSHostingController(rootView: view)
            let sheetWindow = NSWindow(contentViewController: hosting)
            sheet = sheetWindow
            self.refreshCaseChrome()
            await window.beginSheet(sheetWindow)
        }
    }

    /// Asks before submitting a page to a public archive.
    ///
    /// Confirmed every time rather than remembered, because this is the one action in the app
    /// that publishes something: it tells the Internet Archive to fetch the page, and the
    /// resulting capture is public and permanent. An investigator who archives a subject's
    /// page has told anyone who looks that the page was of interest to someone.
    private func confirmArchiveSubmission(for pageURL: URL, from tab: BrowserTab) {
        guard let window, let saveURL = ArchiveLookup.saveRequestURL(for: pageURL) else { return }

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Submit this page to the Wayback Machine?"
        alert.informativeText = pageURL.absoluteString + "\n\n"
            + "The Internet Archive will fetch this page and keep a public, permanent copy. "
            + "Anyone can see that the page was archived and when.\n\n"
            + "If the subject monitors their own site or the archive, this can reveal that "
            + "they are being looked at."
        alert.addButton(withTitle: "Submit")
        alert.addButton(withTitle: "Cancel")
        alert.buttons.first?.hasDestructiveAction = true

        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn else { return }
            self?.openPivot(saveURL, from: tab)
        }
    }

    // MARK: Bookmarks

    /// Handles an address bar entry, which may be a bookmark keyword rather than an address.
    ///
    /// Checked before the address resolver so that a keyword like `ddg` reaches its bookmark
    /// instead of being treated as a single word and handed to a search engine.
    private func handleAddressEntry(_ input: String) {
        let trimmed = input.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }

        // "keyword rest of the words" runs the bookmark's search with those words.
        let parts = trimmed.split(separator: " ", maxSplits: 1)
        if let first = parts.first?.lowercased(),
           let match = bookmarks.all.first(where: { $0.keyword?.lowercased() == first }) {
            let query = parts.count > 1 ? String(parts[1]) : nil
            if let url = match.resolvedURL(query: query) {
                bookmarks.recordUse(id: match.id)
                selectedTab?.load(url)
                return
            }
        }

        // A bookmarked search opened without a term should land on the site rather than send
        // a literal placeholder to someone's endpoint.
        if let bookmark = bookmarks.existing(for: trimmed), bookmark.isSearch,
           let url = bookmark.resolvedURL(query: nil) {
            bookmarks.recordUse(id: bookmark.id)
            selectedTab?.load(url)
            return
        }

        selectedTab?.load(userInput: trimmed)
    }

    /// Bookmarks the current page, or removes the bookmark if there already is one.
    @objc func toggleBookmark() {
        guard let tab = selectedTab, let url = tab.url,
              let scheme = url.scheme, scheme == "http" || scheme == "https" else {
            NSSound.beep()
            return
        }

        if let existing = bookmarks.existing(for: url.absoluteString) {
            try? bookmarks.remove(id: existing.id)
            content.ledger.line = "Removed bookmark — \(existing.title)"
            content.ledger.accent = Palette.textSecondary
        } else {
            let bookmark = Bookmark(
                title: tab.title.isEmpty ? (url.host ?? url.absoluteString) : tab.title,
                url: url.absoluteString,
                folder: "Unsorted"
            )
            try? bookmarks.add(bookmark)
            content.ledger.line = "Bookmarked \(bookmark.title) — in Unsorted"
            content.ledger.accent = Palette.statusCapture
        }
        rebuildBookmarksMenu()
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            self?.refreshCaseChrome()
        }
    }

    @objc func openBookmark(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID,
              let bookmark = bookmarks.bookmark(withID: id),
              let url = bookmark.resolvedURL() else { return }
        bookmarks.recordUse(id: id)
        if let tab = createTab(in: activeContainer) { tab.load(url) }
    }

    /// Rebuilds the Bookmarks menu from the store.
    ///
    /// Folders become submenus, which keeps a hundred entries navigable — a flat menu that
    /// long is slower to use than typing the address.
    func rebuildBookmarksMenu() {
        guard let menu = NSApp.mainMenu?.items
            .first(where: { $0.submenu?.title == "Bookmarks" })?.submenu else { return }

        menu.removeAllItems()

        let add = menu.addItem(withTitle: "Bookmark This Page",
                               action: #selector(toggleBookmark), keyEquivalent: "d")
        add.keyEquivalentModifierMask = [.command]
        menu.addItem(withTitle: "Manage Bookmarks…",
                     action: #selector(showBookmarkManager), keyEquivalent: "")
        menu.addItem(.separator())

        for folder in bookmarks.folders() {
            let entries = bookmarks.bookmarks(inFolder: folder)
            guard !entries.isEmpty else { continue }
            let folderItem = NSMenuItem(title: folder, action: nil, keyEquivalent: "")
            let submenu = NSMenu(title: folder)
            for bookmark in entries {
                let item = NSMenuItem(
                    title: bookmark.requiresAccount ? "\(bookmark.title) (account)" : bookmark.title,
                    action: #selector(openBookmark(_:)), keyEquivalent: "")
                item.representedObject = bookmark.id
                item.target = self
                item.toolTip = [bookmark.url, bookmark.note].compactMap { $0 }.joined(separator: "\n")
                submenu.addItem(item)
            }
            folderItem.submenu = submenu
            menu.addItem(folderItem)
        }
    }

    @objc func showBookmarkManager() {
        guard let window else { return }
        var sheet: NSWindow?

        let view = BookmarkManagerView(
            bookmarks: bookmarks.all,
            folders: bookmarks.folders(),
            onOpen: { [weak self] bookmark in
                sheet.map { window.endSheet($0) }
                guard let self, let url = bookmark.resolvedURL() else { return }
                self.bookmarks.recordUse(id: bookmark.id)
                if let tab = self.createTab(in: self.activeContainer) { tab.load(url) }
            },
            onUpdate: { [weak self] bookmark in
                try? self?.bookmarks.update(bookmark)
                self?.rebuildBookmarksMenu()
            },
            onRemove: { [weak self] bookmark in
                try? self?.bookmarks.remove(id: bookmark.id)
                self?.rebuildBookmarksMenu()
                sheet.map { window.endSheet($0) }
                self?.showBookmarkManager()
            },
            onClose: { sheet.map { window.endSheet($0) } }
        )

        let hosting = NSHostingController(rootView: view)
        let sheetWindow = NSWindow(contentViewController: hosting)
        sheet = sheetWindow
        window.beginSheet(sheetWindow)
    }

    // MARK: Monitoring

    /// Sets up a watch on the current page.
    @objc func watchThisPage() {
        guard let tab = selectedTab, let url = tab.url, let window,
              let scheme = url.scheme, scheme == "http" || scheme == "https" else {
            NSSound.beep()
            return
        }

        let identity = tab.identity
        var sheet: NSWindow?
        let view = WatchEditorView(
            name: tab.title.isEmpty ? (url.host ?? "Page") : tab.title,
            interval: .hourly,
            sensitivity: .moderate,
            recordToCase: cases.isOpen,
            url: url.absoluteString,
            containerName: identity.name,
            caseName: cases.caseName,
            onAdd: { [weak self] name, interval, sensitivity, recordToCase in
                sheet.map { window.endSheet($0) }
                guard let self else { return }
                var watch = Watch(
                    name: name.trimmingCharacters(in: .whitespaces),
                    url: url.absoluteString,
                    containerID: identity.id,
                    interval: interval,
                    sensitivity: sensitivity,
                    casePath: recordToCase ? self.cases.casePath : nil
                )
                // Seed the baseline from the page already on screen, so the first scheduled
                // check compares against what the investigator actually saw rather than
                // reporting a change simply because it is the first look.
                watch.lastCheckedAt = Date()
                try? self.watches.add(watch)
                self.watchRunner.checkNow(watch)
                self.content.ledger.line = "Watching \(watch.name) · \(interval.displayName)"
                self.content.ledger.accent = Palette.statusCapture
            },
            onCancel: { sheet.map { window.endSheet($0) } }
        )

        let hosting = NSHostingController(rootView: view)
        let sheetWindow = NSWindow(contentViewController: hosting)
        sheet = sheetWindow
        window.beginSheet(sheetWindow)
    }

    @objc func showWatchList() {
        guard let window else { return }
        var sheet: NSWindow?

        func present() {
            let view = WatchListView(
                watches: self.watches.all,
                containerName: { [weak self] id in
                    self?.identities.identity(withID: id)?.name ?? "Unknown identity"
                },
                onToggle: { [weak self] watch in
                    var updated = watch
                    updated.isEnabled.toggle()
                    try? self?.watches.update(updated)
                    sheet.map { window.endSheet($0) }
                    self?.showWatchList()
                },
                onCheckNow: { [weak self] watch in self?.watchRunner.checkNow(watch) },
                onOpen: { [weak self] watch in
                    sheet.map { window.endSheet($0) }
                    guard let url = URL(string: watch.url),
                          let identity = self?.identities.identity(withID: watch.containerID),
                          let tab = self?.createTab(in: identity) else { return }
                    tab.load(url)
                },
                onRemove: { [weak self] watch in
                    try? self?.watches.remove(id: watch.id)
                    sheet.map { window.endSheet($0) }
                    self?.showWatchList()
                },
                onClose: { sheet.map { window.endSheet($0) } }
            )
            let hosting = NSHostingController(rootView: view)
            let sheetWindow = NSWindow(contentViewController: hosting)
            sheet = sheetWindow
            window.beginSheet(sheetWindow)
        }

        present()
    }

    // MARK: Capture control

    @objc func captureThisPage() {
        guard let tab = selectedTab else { return }
        guard cases.isOpen else {
            presentSessionFailure(CaseError.noCaseOpen)
            return
        }

        cases.captureNow(tab) { [weak self] result in
            guard let self, let window = self.window else { return }
            switch result {
            case .success(let count):
                // Brief, in the ledger rather than a dialog: this is a command an
                // investigator will use repeatedly, and a modal each time would be punishing.
                self.content.ledger.line = "Captured \(count) artifact(s) from this page"
                self.content.ledger.accent = Palette.statusCapture
                Task { [weak self] in
                    try? await Task.sleep(for: .seconds(4))
                    self?.refreshCaseChrome()
                }
            case .failure(let error):
                let alert = NSAlert()
                alert.messageText = "Nothing was captured"
                alert.informativeText = error.localizedDescription
                alert.addButton(withTitle: "OK")
                alert.beginSheetModal(for: window)
            }
        }
    }

    @objc func setCaptureModeContinuous() { setCaptureMode(.continuous) }
    @objc func setCaptureModeManual() { setCaptureMode(.manual) }
    @objc func setCaptureModePaused() { setCaptureMode(.paused) }

    private func setCaptureMode(_ mode: CaptureMode) {
        cases.captureMode = mode
        refreshCaseChrome()

        // Announced in the ledger, because a mode change that leaves no trace is how an
        // investigator ends up believing they are recording when they are not.
        content.ledger.line = "\(mode.displayName) — \(mode.explanation)"
        content.ledger.accent = mode == .paused ? Palette.statusWarn : Palette.statusCapture
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(6))
            self?.refreshCaseChrome()
        }
    }

    @objc func signCase() {
        guard let window else { return }
        do {
            let manifest = try cases.writeManifest()
            let alert = NSAlert()
            alert.messageText = "Manifest signed"
            alert.informativeText = "\(manifest.entries.count) artifact(s) listed and signed.\n\n"
                + "manifest.json and manifest.sig sit beside the case database. They record "
                + "what this case holds and that the list has not been altered since signing. "
                + "They do not, on their own, prove when the pages were captured — that needs "
                + "a trusted timestamp from a third party."
            alert.addButton(withTitle: "OK")
            alert.beginSheetModal(for: window)
        } catch {
            presentSessionFailure(error)
        }
    }

    /// Timestamps without any interface, for the command-line path.
    func timestampCaseWithoutUI() async throws -> Date {
        try await cases.timestampManifest()
    }

    @objc func timestampCase() {
        guard cases.isOpen, let window else {
            NSSound.beep()
            return
        }

        content.ledger.line = "Requesting a trusted timestamp…"
        content.ledger.accent = Palette.textSecondary

        Task { [weak self] in
            guard let self else { return }
            do {
                let when = try await self.cases.timestampManifest()
                let alert = NSAlert()
                alert.messageText = "Timestamp obtained"
                alert.informativeText = "An independent authority has attested that this "
                    + "case's manifest existed as of "
                    + when.formatted(date: .abbreviated, time: .standard) + ".\n\n"
                    + "The authority received only a SHA-256 hash — not the manifest, not the "
                    + "case, nothing about the subject. The token travels with unfiltered "
                    + "exports."
                alert.addButton(withTitle: "OK")
                await alert.beginSheetModal(for: window)
            } catch {
                let alert = NSAlert()
                alert.alertStyle = .warning
                alert.messageText = "No timestamp was obtained"
                // Explicit, because a failed timestamp leaves the case exactly as it was and
                // an investigator must not come away thinking timing has been established.
                alert.informativeText = error.localizedDescription
                    + "\n\nThe case is unchanged and remains signed, but its timing is not "
                    + "independently attested."
                alert.addButton(withTitle: "OK")
                await alert.beginSheetModal(for: window)
            }
            self.refreshCaseChrome()
        }
    }

    @objc func verifyCase() {
        guard let window else { return }
        do {
            let report = try cases.verify()
            let manifest = try cases.verifyManifest()
            let alert = NSAlert()
            let clean = report.isClean && manifest.isValid
            alert.alertStyle = clean ? .informational : .critical
            alert.messageText = clean ? "Case verified" : "Case failed verification"
            var detail = report.summary + "\n" + manifest.summary
            if !report.altered.isEmpty {
                detail += "\n\nAltered:\n" + report.altered.joined(separator: "\n")
            }
            if !report.missing.isEmpty {
                detail += "\n\nMissing:\n" + report.missing.joined(separator: "\n")
            }
            if !report.unreferenced.isEmpty {
                detail += "\n\n\(report.unreferenced.count) stored artifact(s) referenced by nothing."
            }
            alert.informativeText = detail
            alert.beginSheetModal(for: window)
        } catch {
            presentSessionFailure(error)
        }
    }

    /// Reflects whether a case is open, and how much is in it.
    private func refreshCaseChrome() {
        if let name = cases.caseName {
            let mode = cases.captureMode
            // Paused is the only mode that can lose something, so it reads as a warning
            // everywhere rather than as a neutral state.
            identityStrip.capture = mode == .paused
                ? .degraded("Recording paused")
                : .capturing
            captureButton.contentTintColor = mode == .continuous
                ? Palette.textSecondary
                : Palette.statusCapture

            if let host = cases.captureInProgress {
                content.ledger.line = "Capturing \(host) — archiving, screenshot, PDF"
            } else {
                content.ledger.line = "\(mode.statusLabel) to \(name) · \(cases.visitCount) page"
                    + (cases.visitCount == 1 ? "" : "s")
                    + (mode == .manual ? " · ⇧⌘R to capture this one" : "")
            }
            content.ledger.accent = mode == .paused ? Palette.statusWarn : Palette.statusCapture
        } else {
            identityStrip.capture = .off
            ledgerIdle()
        }
        inspector.update(
            for: selectedTab,
            caseIsOpen: cases.isOpen,
            recordedDigest: selectedTab?.url.flatMap { cases.recordedDigest(for: $0) },
            artifacts: selectedTab?.url.map { cases.artifacts(for: $0) } ?? []
        )
    }

    /// Makes `identity` the active identity.
    ///
    /// Existing tabs are untouched — they stay bound to the identity they were born in.
    /// Only *new* tabs follow the switch, which is what keeps a logged-in persona from
    /// silently becoming a different one under a tab the investigator is already using.
    private func switchTo(_ identity: Identity) {
        guard identity.id != activeContainer.id else { return }
        activeContainer = identity
        reloadSidebar()
        checkEgress()
    }

    private func presentEditor(for identity: Identity?) {
        guard let window else { return }

        let isNew = identity == nil
        let subject = identity ?? Identity(
            name: "New identity",
            color: IdentityColor.suggested(forExistingCount: identities.all.count)
        )
        let password = identity.flatMap { ProxyCredentialStore.password(forContainer: $0.id) }

        var hosting: NSViewController?
        let view = IdentityEditorView(
            draft: IdentityDraft(identity: subject, password: password),
            isNew: isNew,
            onSave: { [weak self] edited, password in
                hosting.map { window.endSheet($0.view.window!) }
                self?.save(edited, password: password, isNew: isNew)
            },
            onCancel: {
                hosting.map { window.endSheet($0.view.window!) }
            }
        )

        let controller = NSHostingController(rootView: view)
        hosting = controller
        window.beginSheet(NSWindow(contentViewController: controller))
    }

    private func save(_ identity: Identity, password: String?, isNew: Bool) {
        do {
            if let password {
                try ProxyCredentialStore.save(password: password, forContainer: identity.id)
            } else {
                try? ProxyCredentialStore.delete(forContainer: identity.id)
            }

            if isNew {
                try identities.add(identity)
            } else {
                try identities.update(identity)
                // Push the new egress onto the live session so the change takes effect on
                // the identity's next load rather than at next launch.
                try sessions.refreshProxy(for: identity)
                sessions.refreshBlocking(for: identity)
            }

            if activeContainer.id == identity.id {
                activeContainer = identity
                checkEgress()
            }
            reloadSidebar()
        } catch {
            presentSessionFailure(error)
        }
    }

    private func confirmDelete(_ identity: Identity) {
        guard let window else { return }

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Delete “\(identity.name)”?"
        // Spelled out because this is unrecoverable and the consequence is not obvious:
        // the persona is logged out of everything it had a session with.
        alert.informativeText = "Its cookies, logins and local storage will be erased from "
            + "this Mac. Any tabs still open in it will keep working until you close them. "
            + "This cannot be undone."
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        alert.buttons.first?.hasDestructiveAction = true

        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn, let self else { return }
            Task {
                await self.sessions.destroySession(for: identity)
                try? self.identities.remove(id: identity.id)
                if self.activeContainer.id == identity.id {
                    self.activeContainer = self.identities.identity(withID: Identity.personal.id) ?? .personal
                }
                self.reloadSidebar()
            }
        }
    }

    // MARK: Find on page

    @objc func showFindBar() {
        content.setFindBarVisible(true)
    }

    private func hideFindBar() {
        content.setFindBarVisible(false)
        window?.makeFirstResponder(selectedTab?.webView)
    }

    @objc func findNext() { stepFind(forward: true) }
    @objc func findPrevious() { stepFind(forward: false) }

    private func stepFind(forward: Bool) {
        guard content.isFindBarVisible else {
            showFindBar()
            return
        }
        content.findBar.step(forward: forward)
    }

    private func performFind(_ query: String, forward: Bool?) {
        guard let webView = selectedTab?.webView, !query.isEmpty else {
            content.findBar.showResult(matched: true)
            return
        }

        let configuration = WKFindConfiguration()
        configuration.backwards = (forward == false)
        // A fresh query restarts from the top; stepping continues from the current match.
        configuration.wraps = true
        configuration.caseSensitive = false

        webView.find(query, configuration: configuration) { [weak self] result in
            MainActor.assumeIsolated {
                self?.content.findBar.showResult(matched: result.matchFound)
            }
        }
    }

    // MARK: Zoom

    @objc func zoomIn() { selectedTab?.adjustZoom(by: 0.1) }
    @objc func zoomOut() { selectedTab?.adjustZoom(by: -0.1) }
    @objc func zoomReset() { selectedTab?.resetZoom() }

    @objc func reloadPage() { selectedTab?.reload() }
    @objc func goBack() { selectedTab?.goBack() }
    @objc func goForward() { selectedTab?.goForward() }

    // MARK: Tab switching

    /// Selects a tab by its position, for ⌘1 through ⌘8. ⌘9 selects the last tab,
    /// matching Safari and Chrome.
    @objc func selectTabByNumber(_ sender: NSMenuItem) {
        let number = sender.tag
        guard !tabs.isEmpty else { return }
        let tab = number == 9 ? tabs.last : (tabs.indices.contains(number - 1) ? tabs[number - 1] : nil)
        guard let tab else { return }
        select(tab.id)
    }

    @objc func selectNextTab() { cycleTab(by: 1) }
    @objc func selectPreviousTab() { cycleTab(by: -1) }

    private func cycleTab(by offset: Int) {
        guard tabs.count > 1, let current = tabs.firstIndex(where: { $0.id == selectedTabID }) else { return }
        // Wrap, so repeated presses walk the whole strip rather than stalling at the ends.
        let next = (current + offset + tabs.count) % tabs.count
        select(tabs[next].id)
    }

    // MARK: Tabs

    /// Opens a URL, reusing the current tab if it has never been navigated.
    ///
    /// Without this, launching with a URL — or opening one from another app — strands the
    /// empty tab the window starts with beside the page the user actually asked for.
    @discardableResult
    func open(_ url: URL) -> BrowserTab? {
        let tab: BrowserTab?
        // `hasBeenAskedToLoad` rather than `url == nil`: the latter is only true until WebKit
        // gets round to reporting the navigation, which is long enough for a second call to
        // decide the same tab is still free.
        if let current = selectedTab, !current.hasBeenAskedToLoad {
            tab = current
        } else {
            tab = createTab(in: activeContainer)
        }
        tab?.load(url)
        return tab
    }

    @objc func newTab() {
        createTab(in: activeContainer)
    }

    /// Creates a tab bound to `identity`.
    ///
    /// Returns nil when the identity's session could not be built — a malformed proxy, or
    /// a missing credential. No web view is created in that case, which is the point: a
    /// identity that cannot reach its proxy must not fall back to the machine's own
    /// connection, because the investigator would not notice until they were already
    /// browsing a subject's site from their home address.
    @discardableResult
    private func createTab(in identity: Identity) -> BrowserTab? {
        let configuration: WKWebViewConfiguration
        do {
            configuration = try sessions.configuration(for: identity)
        } catch {
            presentSessionFailure(error)
            return nil
        }

        prepareContextReporting(on: configuration.userContentController)
        prepareTrackerReporting(on: configuration.userContentController)

        let tab = BrowserTab(configuration: configuration, identity: identity)
        tab.onDidFinishNavigation = { [weak self] tab in self?.cases.record(tab) }
        tab.pivotItemProvider = { [weak self] target in
            guard let self else { return [] }
            return PivotMenuBuilder.items(
                for: target,
                // Pivots open in the identity the investigator is already working as, so a
                // lookup carries that identity's egress rather than silently reverting to the
                // machine's own connection.
                open: { [weak self] url in self?.openPivot(url, from: tab) },
                inspectImage: { [weak self] url in self?.inspectImage(url, in: tab) },
                transcribeImage: { [weak self] url in self?.transcribeImage(url, in: tab) }
            )
        }
        tabs.append(tab)
        tab.setReaderDark(readerDarkEnabled)   // new tabs inherit the global dark-mode choice

        // Redraw the chrome whenever anything user-visible about the tab changes. These
        // fire after the model has been updated, so the chrome reads current values.
        var cancellables = Set<AnyCancellable>()
        tab.didChange.sink { [weak self] in self?.refreshChrome() }.store(in: &cancellables)
        tab.progressDidChange.sink { [weak self] in self?.refreshProgress() }.store(in: &cancellables)
        tabObservers[tab.id] = cancellables

        select(tab.id)
        addressField.focus()
        return tab
    }

    /// Installs the context-menu script and handler on a identity's controller, once.
    private func prepareContextReporting(on controller: WKUserContentController) {
        contextRelay.resolveTab = { [weak self] webView in
            self?.tabs.first { $0.webView === webView }
        }
        contextInstaller.install(on: controller, handler: contextRelay)
    }

    // MARK: Behavioural tracker blocking

    private func prepareTrackerReporting(on controller: WKUserContentController) {
        trackerRelay.onReport = { [weak self] firstParty, thirdParties in
            self?.handleTrackerReport(firstParty: firstParty, thirdParties: thirdParties)
        }
        if trackerReportingControllers.insert(ObjectIdentifier(controller)).inserted {
            controller.add(trackerRelay, name: TrackerReportRelay.messageName)
            controller.addUserScript(WKUserScript(
                source: Self.trackerReporterScript,
                injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        }
        // Apply whatever was learned in earlier sessions, once.
        if !didApplyLearnedTrackers {
            didApplyLearnedTrackers = true
            recompileBehavioral()
        }
    }

    private func handleTrackerReport(firstParty: String, thirdParties: [String]) {
        // Recompile only when a new domain crossed the threshold — not on every page.
        if behaviorLearner.observe(firstParty: firstParty, thirdParties: thirdParties) {
            recompileBehavioral()
        }
    }

    private func recompileBehavioral() {
        let trackers = behaviorLearner.trackers()
        guard !trackers.isEmpty else {
            sessions.setBehavioralRuleList(nil)
            return
        }
        let rules: [[String: Any]] = trackers.map { domain in
            let escaped = NSRegularExpression.escapedPattern(for: domain)
            return [
                "trigger": ["url-filter": "^https?://([^/]*\\.)?\(escaped)", "load-type": ["third-party"]],
                "action": ["type": "block"],
            ]
        }
        guard let data = try? JSONSerialization.data(withJSONObject: rules),
              let json = String(data: data, encoding: .utf8) else { return }
        WKContentRuleListStore.default().compileContentRuleList(
            forIdentifier: "shinobi-behavioral", encodedContentRuleList: json
        ) { [weak self] ruleList, error in
            guard let self, let ruleList, error == nil else { return }
            self.sessions.setBehavioralRuleList(ruleList)
        }
    }

    @objc func forgetLearnedTrackers() {
        behaviorLearner.reset()
        sessions.setBehavioralRuleList(nil)
    }

    /// Reports the page's third-party domains (from its resource timings) so the learner can
    /// spot the ones that follow the investigator from site to site.
    static let trackerReporterScript = """
    (function () {
        try {
            const registrable = (host) => {
                const parts = host.split('.');
                return parts.length <= 2 ? host : parts.slice(-2).join('.');
            };
            const first = registrable(location.hostname);
            const seen = new Set();
            for (const entry of performance.getEntriesByType('resource')) {
                try {
                    const host = new URL(entry.name).hostname;
                    if (!host) continue;
                    const domain = registrable(host);
                    if (domain && domain !== first) seen.add(domain);
                } catch (_) {}
            }
            if (seen.size) {
                window.webkit.messageHandlers.\(TrackerReportRelay.messageName).postMessage({
                    firstParty: first, thirdParties: Array.from(seen)
                });
            }
        } catch (_) {}
    })();
    """

    private func presentSessionFailure(_ error: Error) {
        guard let window else { return }
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = "Shinobi did not open the page"
        alert.informativeText = error.localizedDescription
        alert.addButton(withTitle: "OK")
        alert.beginSheetModal(for: window)
    }

    private func select(_ id: UUID) {
        selectedTabID = id
        content.show(selectedTab?.webView)
        refreshChrome()
    }

    /// Redraws progress for the visible tab. Background tabs load without moving the bar —
    /// a progress line that reflects a tab you are not looking at is noise.
    private func refreshProgress() {
        let tab = selectedTab
        content.setProgress(tab?.progress ?? 0, isLoading: tab?.isLoading ?? false)
    }

    private func closeTab(_ id: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        tabs.remove(at: index)
        tabObservers.removeValue(forKey: id)

        if selectedTabID == id {
            // Select the neighbour to the right, falling back to the left.
            let next = tabs.indices.contains(index) ? tabs[index] : tabs.last
            selectedTabID = next?.id
            content.show(next?.webView)
        }

        if tabs.isEmpty {
            // Closing the last tab closes the window, matching Safari.
            window?.performClose(nil)
            return
        }

        refreshChrome()
    }

    @objc func closeCurrentTab() {
        guard let selectedTabID else { return }
        closeTab(selectedTabID)
    }

    @objc func focusAddressField() { addressField.focus() }

    private var dossierWindow: NSWindow?

    @objc func showDossier() {
        let entries = cases.dossier()
        guard !entries.isEmpty else {
            let alert = NSAlert()
            alert.messageText = "No dossier yet"
            alert.informativeText = "Open a case and browse — Shinobi harvests the names, emails, "
                + "domains, phone numbers and other identifiers it finds into the case dossier."
            alert.runModal()
            return
        }

        let body = NSMutableAttributedString()
        let grouped = Dictionary(grouping: entries, by: \.kind)
        for kind in grouped.keys.sorted(by: { dossierLabel($0) < dossierLabel($1) }) {
            body.append(NSAttributedString(string: dossierLabel(kind).uppercased() + "\n", attributes: [
                .font: Typography.sectionHeader, .foregroundColor: Palette.textSecondary,
            ]))
            for entity in grouped[kind]!.sorted(by: { $0.occurrences > $1.occurrences }) {
                let pages = entity.occurrences == 1 ? "1 page" : "\(entity.occurrences) pages"
                body.append(NSAttributedString(string: "  \(entity.value)\u{2003}·\u{2003}\(pages)\n", attributes: [
                    .font: Typography.mono, .foregroundColor: Palette.textPrimary,
                ]))
            }
            body.append(NSAttributedString(string: "\n"))
        }

        let textView = NSTextView()
        textView.isEditable = false
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 16, height: 14)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textStorage?.setAttributedString(body)

        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = true
        scroll.backgroundColor = Palette.windowBackground
        scroll.documentView = textView

        let window = dossierWindow ?? NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 560),
            styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = "Case Dossier"
        window.contentView = scroll
        if dossierWindow == nil { window.center() }
        dossierWindow = window
        window.makeKeyAndOrderFront(nil)
    }

    private func dossierLabel(_ raw: String) -> String {
        Entity.Kind(rawValue: raw)?.displayName
            ?? NamedEntities.Mention.Kind(rawValue: raw)?.displayName
            ?? raw.capitalized
    }

    @objc func toggleReaderDark() {
        readerDarkEnabled.toggle()
        UserDefaults.standard.set(readerDarkEnabled, forKey: "com.shinobi.browser.readerDark")
        for tab in tabs { tab.setReaderDark(readerDarkEnabled) }
    }

    @objc func toggleSidebar() {
        guard let sidebarItem else { return }
        sidebarItem.animator().isCollapsed.toggle()
    }

    @objc func toggleInspector() {
        guard let inspectorItem else { return }
        inspectorItem.animator().isCollapsed.toggle()
    }

    // MARK: Navigation

    @objc private func navigate(_ sender: NSSegmentedControl) {
        switch sender.selectedSegment {
        case 0: selectedTab?.goBack()
        default: selectedTab?.goForward()
        }
    }

    @objc private func reloadOrStop() {
        guard let tab = selectedTab else { return }
        tab.isLoading ? tab.stop() : tab.reload()
    }

    // MARK: Chrome

    private func refreshChrome() {
        content.tabBar.update(tabs: tabs, selected: selectedTabID)

        let tab = selectedTab
        addressField.setAddress(tab?.url, isSecure: tab?.isSecure ?? false)
        inspector.update(
            for: tab,
            caseIsOpen: cases.isOpen,
            recordedDigest: tab?.url.flatMap { cases.recordedDigest(for: $0) },
            artifacts: tab?.url.map { cases.artifacts(for: $0) } ?? []
        )

        navigationControl.setEnabled(tab?.canGoBack ?? false, forSegment: 0)
        navigationControl.setEnabled(tab?.canGoForward ?? false, forSegment: 1)

        let isLoading = tab?.isLoading ?? false
        reloadButton.image = NSImage(
            systemSymbolName: isLoading ? "xmark" : "arrow.clockwise",
            accessibilityDescription: isLoading ? "Stop" : "Reload"
        )

        window?.title = tab?.title ?? "Shinobi"
        refreshProgress()
        refreshEntities(for: tab)
        refreshCaseChrome()
    }

    /// The ledger's resting state, used only when no case is open.
    ///
    /// Never call this directly to clear a transient message — go through
    /// `refreshCaseChrome()`, which reports the state that actually holds.
    private func ledgerIdle() {
        content.ledger.line = "No case open — pages are not being preserved"
        content.ledger.accent = Palette.textTertiary
    }
}

// MARK: - Toolbar

private extension NSToolbarItem.Identifier {
    static let navigation = NSToolbarItem.Identifier("shinobi.navigation")
    static let reload = NSToolbarItem.Identifier("shinobi.reload")
    static let address = NSToolbarItem.Identifier("shinobi.address")
    static let capture = NSToolbarItem.Identifier("shinobi.capture")
}

extension BrowserWindowController: NSToolbarDelegate {

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.navigation, .reload, .address, .flexibleSpace, .capture]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }

    func toolbar(
        _ toolbar: NSToolbar,
        itemForItemIdentifier identifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        let item = NSToolbarItem(itemIdentifier: identifier)
        switch identifier {
        case .navigation:
            item.view = navigationControl
            item.label = "Navigation"
        case .reload:
            item.view = reloadButton
            item.label = "Reload"
        case .capture:
            item.view = captureButton
            item.label = "Capture"
        case .address:
            item.view = addressField
            item.label = "Address"
            // Wide enough to hold a long URL without truncating the host, but willing to
            // give the width back when the window is narrow.
            let width = addressField.widthAnchor.constraint(equalToConstant: 420)
            width.priority = .defaultLow
            NSLayoutConstraint.activate([
                width,
                addressField.widthAnchor.constraint(greaterThanOrEqualToConstant: 240),
                addressField.widthAnchor.constraint(lessThanOrEqualToConstant: 720),
            ])
        default:
            return nil
        }
        return item
    }
}
