// SPDX-License-Identifier: GPL-3.0-or-later
import AppKit
import IdentityKit
import ShinobiKit

/// The left sidebar: cases, identities, and a capture count.
///
/// Deliberately not an `NSOutlineView` in `.sourceList` style. macOS 26 gives the system
/// source list an inset, rounded, floating treatment; Shinobi's panes are flat and separated
/// by hairlines, and a plain table with custom row drawing keeps that without fighting the
/// framework.
@MainActor
final class SidebarViewController: NSViewController {

    enum Row {
        case header(title: String, showsAddButton: Bool)
        case identity(Identity, isActive: Bool)
        case placeholder(title: String, badge: String?)
    }

    var onSelectContainer: ((Identity) -> Void)?
    var onAddContainer: (() -> Void)?
    var onEditContainer: ((Identity) -> Void)?
    var onDeleteContainer: ((Identity) -> Void)?

    private var rows: [Row] = []
    private let tableView = NSTableView()
    private let scrollView = NSScrollView()

    override func loadView() {
        view = NSView()
        view.wantsLayer = true
        view.setLayerBackground(Palette.windowBackground)

        tableView.headerView = nil
        tableView.backgroundColor = .clear
        tableView.selectionHighlightStyle = .none   // selection is drawn by the row view
        tableView.intercellSpacing = .zero
        tableView.gridStyleMask = []
        tableView.rowSizeStyle = .custom
        tableView.dataSource = self
        tableView.delegate = self
        tableView.usesAutomaticRowHeights = false
        tableView.target = self
        tableView.action = #selector(rowClicked)
        tableView.menu = makeContextMenu()

        let column = NSTableColumn(identifier: .init("main"))
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)

        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.automaticallyAdjustsContentInsets = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    // MARK: Contents

    func reload(identities: [Identity], activeID: UUID, caseName: String?, captureCount: Int) {
        rows = [.header(title: "Case", showsAddButton: false)]
        rows.append(.placeholder(title: caseName ?? "No case open", badge: nil))

        rows.append(.header(title: "Identities", showsAddButton: true))
        rows.append(contentsOf: identities.map { .identity($0, isActive: $0.id == activeID) })

        rows.append(.header(title: "Recorded", showsAddButton: false))
        rows.append(.placeholder(
            title: caseName == nil ? "Nothing" : (captureCount == 1 ? "1 page" : "\(captureCount) pages"),
            badge: nil
        ))

        tableView.reloadData()
    }

    private func identity(atRow row: Int) -> Identity? {
        guard rows.indices.contains(row), case .identity(let identity, _) = rows[row] else { return nil }
        return identity
    }

    // MARK: Actions

    @objc private func rowClicked() {
        guard let identity = identity(atRow: tableView.clickedRow) else { return }
        onSelectContainer?(identity)
    }

    @objc private func addContainer() { onAddContainer?() }

    @objc private func editClicked() {
        guard let identity = identity(atRow: tableView.clickedRow) else { return }
        onEditContainer?(identity)
    }

    @objc private func deleteClicked() {
        guard let identity = identity(atRow: tableView.clickedRow) else { return }
        onDeleteContainer?(identity)
    }

    private func makeContextMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self
        menu.addItem(withTitle: "Edit Identity…", action: #selector(editClicked), keyEquivalent: "")
        menu.addItem(withTitle: "Delete Identity…", action: #selector(deleteClicked), keyEquivalent: "")
        menu.items.forEach { $0.target = self }
        return menu
    }
}

extension SidebarViewController: NSMenuDelegate {
    /// Only offer identity commands on identity rows, and never offer to delete Personal.
    func menuNeedsUpdate(_ menu: NSMenu) {
        let identity = identity(atRow: tableView.clickedRow)
        menu.items[0].isHidden = identity == nil
        menu.items[1].isHidden = identity == nil || identity?.isPersonal == true
    }
}

extension SidebarViewController: NSTableViewDataSource {
    func numberOfRows(in tableView: NSTableView) -> Int { rows.count }
}

extension SidebarViewController: NSTableViewDelegate {

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        switch rows[row] {
        case .header: Typography.headerRowHeight + 10   // breathing room above the header
        default: Typography.rowHeight
        }
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        if case .header(let title, let showsAddButton) = rows[row] {
            return SidebarHeaderView(
                title: title,
                addAction: showsAddButton ? { [weak self] in self?.addContainer() } : nil
            )
        }
        return SidebarRowView(row: rows[row])
    }

    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
        if case .header = rows[row] { return false }
        return true
    }
}

// MARK: - Rows

/// A section heading, optionally carrying an add button.
@MainActor
private final class SidebarHeaderView: NSView {

    private let title: String
    private let addAction: (() -> Void)?
    private var button: NSButton?

    init(title: String, addAction: (() -> Void)?) {
        self.title = title
        self.addAction = addAction
        super.init(frame: .zero)

        guard addAction != nil else { return }
        let button = NSButton()
        button.isBordered = false
        button.bezelStyle = .inline
        button.image = NSImage(systemSymbolName: "plus", accessibilityDescription: "New identity")?
            .withSymbolConfiguration(.init(pointSize: 10, weight: .semibold))
        button.contentTintColor = Palette.textTertiary
        button.target = self
        button.action = #selector(add)
        button.toolTip = "New identity"
        button.translatesAutoresizingMaskIntoConstraints = false
        addSubview(button)
        NSLayoutConstraint.activate([
            button.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Typography.contentInset + 2),
            button.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -1),
            button.widthAnchor.constraint(equalToConstant: 18),
            button.heightAnchor.constraint(equalToConstant: 18),
        ])
        self.button = button
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    @objc private func add() { addAction?() }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let attributed = NSAttributedString(string: title.uppercased(), attributes: [
            .font: Typography.sectionHeader,
            .foregroundColor: Palette.textTertiary,
            .kern: Typography.sectionHeaderTracking,
        ])
        let size = attributed.size()
        // Bottom-aligned, so the extra height reads as space above the header.
        attributed.draw(at: NSPoint(x: Typography.contentInset, y: bounds.maxY - size.height - 4))
    }
}

/// Draws one identity or placeholder line.
@MainActor
private final class SidebarRowView: NSView {

    private let row: SidebarViewController.Row

    init(row: SidebarViewController.Row) {
        self.row = row
        super.init(frame: .zero)
        if case .identity(let identity, _) = row {
            toolTip = identity.proxy.map { "Exits via \($0.displayLabel)" }
                ?? (identity.isPersonal ? "Your own connection" : "No proxy — uses your own connection")
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        switch row {
        case .header:
            break
        case .identity(let identity, let isActive):
            draw(
                title: identity.name,
                color: Palette.color(for: identity.color),
                badge: identity.proxy == nil && !identity.isPersonal ? "!" : nil,
                badgeColor: Palette.statusWarn,
                isSelected: isActive
            )
        case .placeholder(let title, let badge):
            draw(title: title, color: nil, badge: badge, badgeColor: Palette.textTertiary, isSelected: false)
        }
    }

    private func draw(
        title: String,
        color: NSColor?,
        badge: String?,
        badgeColor: NSColor,
        isSelected: Bool
    ) {
        if isSelected {
            Palette.accent.withAlphaComponent(0.22).setFill()
            bounds.fill()
            Palette.accent.setFill()
            NSRect(x: 0, y: 0, width: 2, height: bounds.height).fill()
        }

        var x = Typography.contentInset

        if let color {
            let diameter: CGFloat = 8
            let rect = NSRect(x: x, y: (bounds.height - diameter) / 2, width: diameter, height: diameter)
            color.setFill()
            NSBezierPath(ovalIn: rect).fill()
            x = rect.maxX + 8
        }

        var trailingReserve = Typography.contentInset
        if let badge {
            let attributed = NSAttributedString(string: badge, attributes: [
                .font: Typography.monoSmall,
                .foregroundColor: badgeColor,
            ])
            let size = attributed.size()
            attributed.draw(at: NSPoint(
                x: bounds.maxX - Typography.contentInset - size.width,
                y: (bounds.height - size.height) / 2
            ))
            trailingReserve += size.width + 8
        }

        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byTruncatingTail
        let attributed = NSAttributedString(string: title, attributes: [
            .font: isSelected ? Typography.bodyEmphasised : Typography.body,
            .foregroundColor: isSelected ? Palette.textPrimary : Palette.textSecondary,
            .paragraphStyle: style,
        ])
        let size = attributed.size()
        attributed.draw(in: NSRect(
            x: x,
            y: (bounds.height - size.height) / 2,
            width: max(0, bounds.width - x - trailingReserve),
            height: size.height
        ))
    }
}
