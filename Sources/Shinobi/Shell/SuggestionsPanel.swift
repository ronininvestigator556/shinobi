// SPDX-License-Identifier: GPL-3.0-or-later
import AppKit
import BookmarkKit
import ShinobiKit

/// A list of bookmark suggestions shown beneath the address bar.
///
/// Written rather than using AppKit's built-in field completion, which is the wrong mechanism
/// for this. That API completes a *prefix*: it inserts the matched text into the field and
/// selects the remainder. Handing it whole addresses meant typing two characters replaced the
/// line with `https://…`, and every further keystroke overwrote the selection — the field
/// became impossible to type in.
///
/// This panel never touches what has been typed. It shows what is available and waits.
@MainActor
final class SuggestionsPanel: NSObject {

    private let panel = NSPanel(
        contentRect: NSRect(x: 0, y: 0, width: 480, height: 0),
        styleMask: [.borderless, .nonactivatingPanel],
        backing: .buffered,
        defer: true
    )
    private let scrollView = NSScrollView()
    private let tableView = NSTableView()

    private var matches: [BookmarkMatcher.Match] = []
    private weak var anchor: NSView?

    /// Called when a suggestion is chosen.
    var onChoose: ((BookmarkMatcher.Match) -> Void)?

    var isVisible: Bool { panel.isVisible }
    var selectedMatch: BookmarkMatcher.Match? {
        let row = tableView.selectedRow
        return matches.indices.contains(row) ? matches[row] : nil
    }

    override init() {
        super.init()

        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true

        let identity = NSView()
        identity.wantsLayer = true
        identity.layer?.backgroundColor = Palette.panelBackground.cgColor
        identity.layer?.cornerRadius = 6
        identity.layer?.borderWidth = 1
        identity.layer?.borderColor = Palette.separator.cgColor
        identity.layer?.masksToBounds = true

        tableView.headerView = nil
        tableView.backgroundColor = .clear
        tableView.rowHeight = 40
        tableView.intercellSpacing = .zero
        tableView.gridStyleMask = []
        tableView.selectionHighlightStyle = .regular
        tableView.dataSource = self
        tableView.delegate = self
        tableView.target = self
        tableView.action = #selector(rowClicked)
        tableView.addTableColumn(NSTableColumn(identifier: .init("suggestion")))

        scrollView.documentView = tableView
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        identity.addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: identity.topAnchor, constant: 4),
            scrollView.bottomAnchor.constraint(equalTo: identity.bottomAnchor, constant: -4),
            scrollView.leadingAnchor.constraint(equalTo: identity.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: identity.trailingAnchor),
        ])

        panel.contentView = identity
    }

    // MARK: Showing

    func show(_ matches: [BookmarkMatcher.Match], below field: NSView) {
        guard !matches.isEmpty, let window = field.window else {
            hide()
            return
        }

        self.matches = matches
        self.anchor = field
        tableView.reloadData()
        // Nothing is selected initially: the first Return should submit what was typed, not
        // silently navigate to a suggestion the investigator has not looked at.
        tableView.deselectAll(nil)

        let height = min(CGFloat(matches.count), 8) * tableView.rowHeight + 8
        let fieldFrame = field.convert(field.bounds, to: nil)
        let onScreen = window.convertToScreen(fieldFrame)

        panel.setFrame(
            NSRect(x: onScreen.minX, y: onScreen.minY - height - 4,
                   width: max(360, onScreen.width), height: height),
            display: true)

        if panel.parent == nil {
            // A child window so it follows the browser window and cannot be left behind it.
            window.addChildWindow(panel, ordered: .above)
        }
        panel.orderFront(nil)
    }

    func hide() {
        guard panel.isVisible else { return }
        panel.parent?.removeChildWindow(panel)
        panel.orderOut(nil)
        matches = []
    }

    /// Moves the selection. Returns false when there is nothing to move through, so the caller
    /// can let the keystroke do its normal job.
    @discardableResult
    func moveSelection(by delta: Int) -> Bool {
        guard isVisible, !matches.isEmpty else { return false }
        let current = tableView.selectedRow
        var next = current + delta
        if current == -1 { next = delta > 0 ? 0 : matches.count - 1 }
        next = max(0, min(matches.count - 1, next))
        tableView.selectRowIndexes([next], byExtendingSelection: false)
        tableView.scrollRowToVisible(next)
        return true
    }

    @objc private func rowClicked() {
        guard let match = selectedMatch else { return }
        onChoose?(match)
        hide()
    }
}

extension SuggestionsPanel: NSTableViewDataSource {
    func numberOfRows(in tableView: NSTableView) -> Int { matches.count }
}

extension SuggestionsPanel: NSTableViewDelegate {
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard matches.indices.contains(row) else { return nil }
        return SuggestionRowView(match: matches[row])
    }
}

/// One suggestion: what it is called, where it lives, and what it is for.
@MainActor
private final class SuggestionRowView: NSView {

    init(match: BookmarkMatcher.Match) {
        super.init(frame: .zero)

        let bookmark = match.bookmark
        let title = NSTextField(labelWithString: bookmark.title)
        title.font = Typography.bodyEmphasised
        title.textColor = Palette.textPrimary
        title.lineBreakMode = .byTruncatingTail

        let detail = NSTextField(labelWithString:
            [bookmark.folder, bookmark.isSearch ? "search" : nil, bookmark.host]
                .compactMap { $0 }.joined(separator: " · "))
        detail.font = Typography.caption
        detail.textColor = Palette.textSecondary
        detail.lineBreakMode = .byTruncatingMiddle

        let stack = NSStackView(views: [title, detail])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 1
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}
