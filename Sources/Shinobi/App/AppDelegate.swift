// SPDX-License-Identifier: GPL-3.0-or-later
import AppKit
import BookmarkKit
import CaseKit
import IdentityKit
import MonitorKit
import ShinobiKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    private var windowController: BrowserWindowController?
    private let identities = IdentityStore()
    private let sessions = IdentitySessionProvider()
    private let filterLists = FilterListStore()
    private let watches = WatchStore()
    private let bookmarks = BookmarkStore()
    private lazy var blockerCompiler = ContentBlockerCompiler(listStore: filterLists)

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Shinobi follows the system appearance (light or dark), like Safari. The meaning-
        // bearing colours (identity, capture state, integrity status) stay constant across
        // appearances; only the neutral surface/text tokens resolve per appearance — see
        // `Palette`. `NSApp.appearance` is left nil so the system drives it.

        buildMainMenu()

        let controller = BrowserWindowController(identities: identities, sessions: sessions, watches: watches, bookmarks: bookmarks)
        controller.showWindow(nil)
        windowController = controller

        openCaseFromLaunchArguments(into: controller)

        // Maintenance invocations, in the order a hand-off actually happens: obtain a
        // timestamp over the signed manifest, then export. Both quit when finished.
        if CommandLine.arguments.contains("--timestamp") {
            Task { [weak self] in
                do {
                    let when = try await controller.timestampCaseWithoutUI()
                    print("Timestamped at \(when.formatted(Date.ISO8601FormatStyle.shinobiTimestamp))")
                    if let destination = self?.value(ofFlag: "--export") {
                        let summary = try controller.exportCaseWithoutUI(
                            to: URL(fileURLWithPath: destination))
                        print("Exported \(summary.artifactCount) artifact(s)")
                    }
                    NSApp.terminate(nil)
                } catch {
                    FileHandle.standardError.write(
                        Data("Timestamp failed: \(error.localizedDescription)\n".utf8))
                    exit(1)
                }
            }
            return
        }

        // A maintenance invocation: open a case, export it, and quit. Keeps scripted
        // collection and hand-off in one place, and means the export path is exercised
        // without driving the interface.
        if let destination = value(ofFlag: "--export") {
            let url = URL(fileURLWithPath: destination)
            do {
                let summary = try controller.exportCaseWithoutUI(to: url)
                print("Exported \(summary.artifactCount) artifact(s) to \(url.path)")
                NSApp.terminate(nil)
            } catch {
                FileHandle.standardError.write(Data("Export failed: \(error.localizedDescription)\n".utf8))
                exit(1)
            }
            return
        }

        openURLsFromLaunchArguments(into: controller)

        // Compiled off the launch path. Blocking is not correct until this finishes, but a
        // few hundred milliseconds of unblocked loading beats a blank window while tens of
        // thousands of rules compile.
        Task { [weak self] in
            guard let self else { return }
            let reports = await self.blockerCompiler.compileAll()
            for report in reports {
                self.sessions.setRuleList(self.blockerCompiler.ruleList(for: report.level), for: report.level)
            }
            self.windowController?.contentBlockingDidChange(reports)
        }

        NSApp.activate(ignoringOtherApps: true)
    }

    /// Opens (or creates) a case named on the command line, as
    /// `shinobi --case ~/Cases/Durham.shinobicase https://example.com`.
    ///
    /// The hook scripted capture runs are driven through: an investigator can queue a batch
    /// of addresses into a named case without sitting at the browser, and the same path
    /// makes the recording pipeline testable end to end without driving the interface.
    /// The value following a flag on the command line, if any.
    private func value(ofFlag flag: String) -> String? {
        let arguments = CommandLine.arguments
        guard let index = arguments.firstIndex(of: flag),
              arguments.index(after: index) < arguments.endIndex else { return nil }
        return arguments[arguments.index(after: index)]
    }

    private func openCaseFromLaunchArguments(into controller: BrowserWindowController) {
        guard let path = value(ofFlag: "--case") else { return }
        var url = URL(fileURLWithPath: path)
        if url.pathExtension != CaseBundle.fileExtension {
            url = url.appendingPathExtension(CaseBundle.fileExtension)
        }
        controller.openOrCreateCase(at: url)
    }

    /// Opens any URLs passed on the command line, as `shinobi https://example.com`.
    ///
    /// Standard behaviour for a browser, and the hook the capture pipeline will be driven
    /// through from scripts once Phase 3 lands. Arguments are resolved through
    /// `URLResolver` rather than `URL(string:)` so the command line obeys exactly the same
    /// navigate-versus-search rules as the address bar.
    private func openURLsFromLaunchArguments(into controller: BrowserWindowController) {
        var arguments = Array(CommandLine.arguments.dropFirst())
        // Drop flag values; a path is not a URL to navigate to.
        for flag in ["--case", "--export"] {
            if let index = arguments.firstIndex(of: flag) {
                arguments.removeSubrange(index...min(index + 1, arguments.count - 1))
            }
        }
        for argument in arguments where !argument.hasPrefix("-") {
            guard let url = URLResolver.resolve(argument) else { continue }
            controller.open(url)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    /// Sign on the way out. Quitting mid-investigation is the normal way a session ends, and
    /// it should not be the reason a case is left without a manifest.
    func applicationWillTerminate(_ notification: Notification) {
        windowController?.closeCase()
    }

    /// Fetches the current community filter lists and recompiles.
    @objc private func updateFilterLists() {
        Task { [weak self] in
            guard let self else { return }
            do {
                let updated = try await self.filterLists.update()
                let reports = await self.blockerCompiler.compileAll()
                for report in reports {
                    self.sessions.setRuleList(self.blockerCompiler.ruleList(for: report.level), for: report.level)
                }
                self.windowController?.contentBlockingDidChange(reports, updatedSources: updated)
            } catch {
                self.windowController?.reportFilterListFailure(error)
            }
        }
    }

    // MARK: Menu

    /// Built in code rather than loaded from a nib, so the whole shell stays inspectable as
    /// source and buildable from the command line.
    private func buildMainMenu() {
        let mainMenu = NSMenu()

        // Application menu.
        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About Shinobi", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide Shinobi", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let hideOthers = appMenu.addItem(withTitle: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(withTitle: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit Shinobi", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        // File menu.
        let fileMenuItem = NSMenuItem()
        let fileMenu = NSMenu(title: "File")
        fileMenu.addItem(withTitle: "New Tab", action: #selector(BrowserWindowController.newTab), keyEquivalent: "t")
        fileMenu.addItem(withTitle: "Close Tab", action: #selector(BrowserWindowController.closeCurrentTab), keyEquivalent: "w")
        let closeWindow = fileMenu.addItem(withTitle: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        closeWindow.keyEquivalentModifierMask = [.command, .shift]
        fileMenuItem.submenu = fileMenu
        mainMenu.addItem(fileMenuItem)

        // Page menu: what this page contains, as opposed to what the case contains.
        let pageMenuItem = NSMenuItem()
        let pageMenu = NSMenu(title: "Page")
        let analyse = pageMenu.addItem(withTitle: "Analyse Page…", action: #selector(BrowserWindowController.analysePage), keyEquivalent: "a")
        analyse.keyEquivalentModifierMask = [.command, .shift]
        pageMenu.addItem(.separator())
        let watchPage = pageMenu.addItem(withTitle: "Watch This Page…", action: #selector(BrowserWindowController.watchThisPage), keyEquivalent: "w")
        watchPage.keyEquivalentModifierMask = [.command, .shift]
        pageMenu.addItem(withTitle: "Watch List…", action: #selector(BrowserWindowController.showWatchList), keyEquivalent: "")
        pageMenu.addItem(.separator())
        let summarise = pageMenu.addItem(withTitle: "Summarise Page", action: #selector(BrowserWindowController.summarisePage), keyEquivalent: "s")
        summarise.keyEquivalentModifierMask = [.command, .shift]
        pageMenuItem.submenu = pageMenu
        mainMenu.addItem(pageMenuItem)

        // Bookmarks menu. Filled in by the window controller, which owns the store.
        let bookmarksMenuItem = NSMenuItem()
        bookmarksMenuItem.submenu = NSMenu(title: "Bookmarks")
        mainMenu.addItem(bookmarksMenuItem)

        // Case menu. Cases are the unit of work in this app, so they get a top-level menu
        // rather than being buried under File.
        let caseMenuItem = NSMenuItem()
        let caseMenu = NSMenu(title: "Case")
        let newCase = caseMenu.addItem(withTitle: "New Case…", action: #selector(BrowserWindowController.newCase), keyEquivalent: "n")
        newCase.keyEquivalentModifierMask = [.command, .shift]
        let openCase = caseMenu.addItem(withTitle: "Open Case…", action: #selector(BrowserWindowController.openCase), keyEquivalent: "o")
        openCase.keyEquivalentModifierMask = [.command, .shift]
        caseMenu.addItem(withTitle: "Close Case", action: #selector(BrowserWindowController.closeCase), keyEquivalent: "")
        caseMenu.addItem(.separator())
        let capture = caseMenu.addItem(withTitle: "Capture This Page", action: #selector(BrowserWindowController.captureThisPage), keyEquivalent: "r")
        capture.keyEquivalentModifierMask = [.command, .shift]

        let modeItem = NSMenuItem(title: "Recording", action: nil, keyEquivalent: "")
        let modeMenu = NSMenu(title: "Recording")
        modeMenu.addItem(withTitle: CaptureMode.continuous.displayName, action: #selector(BrowserWindowController.setCaptureModeContinuous), keyEquivalent: "")
        modeMenu.addItem(withTitle: CaptureMode.manual.displayName, action: #selector(BrowserWindowController.setCaptureModeManual), keyEquivalent: "")
        modeMenu.addItem(withTitle: CaptureMode.paused.displayName, action: #selector(BrowserWindowController.setCaptureModePaused), keyEquivalent: "")
        modeItem.submenu = modeMenu
        caseMenu.addItem(modeItem)

        caseMenu.addItem(.separator())
        let searchCase = caseMenu.addItem(withTitle: "Search Case…", action: #selector(BrowserWindowController.searchCase), keyEquivalent: "f")
        searchCase.keyEquivalentModifierMask = [.command, .shift]
        caseMenu.addItem(.separator())
        let exportItem = caseMenu.addItem(withTitle: "Export Case…", action: #selector(BrowserWindowController.exportCase), keyEquivalent: "e")
        exportItem.keyEquivalentModifierMask = [.command, .shift]
        caseMenu.addItem(.separator())
        caseMenu.addItem(withTitle: "Write Signed Manifest", action: #selector(BrowserWindowController.signCase), keyEquivalent: "")
        caseMenu.addItem(withTitle: "Request Trusted Timestamp…", action: #selector(BrowserWindowController.timestampCase), keyEquivalent: "")
        caseMenu.addItem(withTitle: "Verify Case Integrity", action: #selector(BrowserWindowController.verifyCase), keyEquivalent: "")
        caseMenuItem.submenu = caseMenu
        mainMenu.addItem(caseMenuItem)

        // Edit menu. Without these the standard editing key equivalents do not reach text
        // fields or the web view.
        let editMenuItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Find on Page…", action: #selector(BrowserWindowController.showFindBar), keyEquivalent: "f")
        editMenu.addItem(withTitle: "Find Next", action: #selector(BrowserWindowController.findNext), keyEquivalent: "g")
        let findPrevious = editMenu.addItem(withTitle: "Find Previous", action: #selector(BrowserWindowController.findPrevious), keyEquivalent: "g")
        findPrevious.keyEquivalentModifierMask = [.command, .shift]
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)

        // View menu.
        let viewMenuItem = NSMenuItem()
        let viewMenu = NSMenu(title: "View")
        let focusAddress = viewMenu.addItem(withTitle: "Open Location", action: #selector(BrowserWindowController.focusAddressField), keyEquivalent: "l")
        focusAddress.keyEquivalentModifierMask = [.command]
        viewMenu.addItem(.separator())
        viewMenu.addItem(withTitle: "Reload Page", action: #selector(BrowserWindowController.reloadPage), keyEquivalent: "r")
        viewMenu.addItem(.separator())
        let toggleSidebar = viewMenu.addItem(withTitle: "Toggle Sidebar", action: #selector(BrowserWindowController.toggleSidebar), keyEquivalent: "s")
        toggleSidebar.keyEquivalentModifierMask = [.command, .control]
        let toggleInspector = viewMenu.addItem(withTitle: "Toggle Inspector", action: #selector(BrowserWindowController.toggleInspector), keyEquivalent: "i")
        toggleInspector.keyEquivalentModifierMask = [.command, .control]
        let fullScreen = viewMenu.addItem(withTitle: "Enter Full Screen", action: #selector(NSWindow.toggleFullScreen(_:)), keyEquivalent: "f")
        fullScreen.keyEquivalentModifierMask = [.command, .control]   // ⌃⌘F, so ⌘F stays Find
        viewMenu.addItem(.separator())
        viewMenu.addItem(withTitle: "Zoom In", action: #selector(BrowserWindowController.zoomIn), keyEquivalent: "+")
        viewMenu.addItem(withTitle: "Zoom Out", action: #selector(BrowserWindowController.zoomOut), keyEquivalent: "-")
        viewMenu.addItem(withTitle: "Actual Size", action: #selector(BrowserWindowController.zoomReset), keyEquivalent: "0")
        viewMenu.addItem(.separator())
        let readerDark = viewMenu.addItem(withTitle: "Dark Mode for Pages", action: #selector(BrowserWindowController.toggleReaderDark), keyEquivalent: "d")
        readerDark.keyEquivalentModifierMask = [.command, .control]
        viewMenuItem.submenu = viewMenu
        mainMenu.addItem(viewMenuItem)

        // Privacy menu: the identity and blocking commands that are not per-window chrome.
        let privacyMenuItem = NSMenuItem()
        let privacyMenu = NSMenu(title: "Privacy")
        privacyMenu.addItem(withTitle: "Check Egress Address", action: #selector(BrowserWindowController.checkEgress), keyEquivalent: "")
        privacyMenu.addItem(.separator())
        let updateItem = privacyMenu.addItem(withTitle: "Update Blocking Lists…", action: #selector(updateFilterLists), keyEquivalent: "")
        updateItem.target = self
        privacyMenu.addItem(.separator())
        privacyMenu.addItem(withTitle: "Forget Learned Trackers", action: #selector(BrowserWindowController.forgetLearnedTrackers), keyEquivalent: "")
        privacyMenuItem.submenu = privacyMenu
        mainMenu.addItem(privacyMenuItem)

        // History menu: Back and Forward on the Safari key equivalents (⌘[ / ⌘]).
        let historyMenuItem = NSMenuItem()
        let historyMenu = NSMenu(title: "History")
        historyMenu.addItem(withTitle: "Back", action: #selector(BrowserWindowController.goBack), keyEquivalent: "[")
        historyMenu.addItem(withTitle: "Forward", action: #selector(BrowserWindowController.goForward), keyEquivalent: "]")
        historyMenuItem.submenu = historyMenu
        mainMenu.addItem(historyMenuItem)

        // Window menu. Tab switching lives here to match Safari, and because ⌘1–9 is
        // muscle memory an investigator brings with them.
        let windowMenuItem = NSMenuItem()
        let windowMenu = NSMenu(title: "Window")
        let nextTab = windowMenu.addItem(withTitle: "Show Next Tab", action: #selector(BrowserWindowController.selectNextTab), keyEquivalent: "]")
        nextTab.keyEquivalentModifierMask = [.command, .shift]
        let previousTab = windowMenu.addItem(withTitle: "Show Previous Tab", action: #selector(BrowserWindowController.selectPreviousTab), keyEquivalent: "[")
        previousTab.keyEquivalentModifierMask = [.command, .shift]
        windowMenu.addItem(.separator())
        for number in 1...9 {
            let title = number == 9 ? "Show Last Tab" : "Show Tab \(number)"
            let item = windowMenu.addItem(
                withTitle: title,
                action: #selector(BrowserWindowController.selectTabByNumber(_:)),
                keyEquivalent: "\(number)"
            )
            item.tag = number
            item.isAlternate = false
        }
        windowMenu.addItem(.separator())
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenuItem.submenu = windowMenu
        mainMenu.addItem(windowMenuItem)
        NSApp.windowsMenu = windowMenu

        NSApp.mainMenu = mainMenu
    }
}
