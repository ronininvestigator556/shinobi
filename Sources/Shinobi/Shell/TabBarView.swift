// SPDX-License-Identifier: GPL-3.0-or-later
import AppKit
import IdentityKit
import ShinobiKit

/// The horizontal tab strip above the web content.
///
/// Tabs shrink as they multiply and then scroll, rather than running off the edge. An earlier
/// version simply let them overflow, which produced a bug that looked like nothing to do with
/// layout: with enough tabs open, a new one was created off-screen and the new-tab button was
/// buried underneath the overflowing tabs, so both ⌘T and clicking + appeared to do nothing at
/// all. Investigators keep a great many tabs open, so the strip has to hold up under that.
@MainActor
final class TabBarView: NSView {

    static let barHeight: CGFloat = 36

    /// Comfortable width when there is room.
    private let maxTabWidth: CGFloat = 240
    /// Preferred width before crowding starts.
    private let minTabWidth: CGFloat = 120
    /// Floor. Below this, tabs stop shrinking and the strip scrolls instead — a tab narrower
    /// than its own favicon tells the investigator nothing and cannot be aimed at.
    private let compactTabWidth: CGFloat = 88
    private let newTabButtonWidth: CGFloat = 36

    private let scrollView = NSScrollView()
    private let tabContainer = FlippedView()
    private let newTabButton = NSButton()

    private var itemViews: [UUID: TabItemView] = [:]
    private var order: [UUID] = []
    private var selected: UUID?

    var onSelect: ((UUID) -> Void)?
    var onClose: ((UUID) -> Void)?
    var onNewTab: (() -> Void)?

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = Palette.panelBackground.cgColor

        scrollView.drawsBackground = false
        scrollView.hasHorizontalScroller = false
        scrollView.hasVerticalScroller = false
        scrollView.horizontalScrollElasticity = .allowed
        scrollView.verticalScrollElasticity = .none
        scrollView.automaticallyAdjustsContentInsets = false
        scrollView.contentView = FlippedClipView()
        scrollView.documentView = tabContainer
        addSubview(scrollView)

        setupNewTabButton()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func setupNewTabButton() {
        newTabButton.bezelStyle = .inline
        newTabButton.isBordered = false
        newTabButton.image = NSImage(
            systemSymbolName: "plus",
            accessibilityDescription: "New tab"
        )?.withSymbolConfiguration(.init(pointSize: 12, weight: .medium))
        newTabButton.contentTintColor = Palette.textSecondary
        newTabButton.target = self
        newTabButton.action = #selector(newTabClicked)
        newTabButton.toolTip = "New Tab (⌘T)"
        newTabButton.wantsLayer = true
        // Opaque, so scrolled tabs pass behind it rather than showing through.
        newTabButton.layer?.backgroundColor = Palette.panelBackground.cgColor

        // Added last, and kept last: the button sits beside the scrolling region, and a tab
        // must never be able to cover the control that creates tabs.
        addSubview(newTabButton, positioned: .above, relativeTo: scrollView)
    }

    @objc private func newTabClicked() { onNewTab?() }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        Palette.separator.setFill()
        NSRect(x: 0, y: bounds.maxY - 1, width: bounds.width, height: 1).fill()
    }

    // MARK: Contents

    /// Reconciles the strip against the current tab list.
    ///
    /// Views are reused by tab id rather than rebuilt, so hover state survives a title change
    /// on an unrelated tab.
    func update(tabs: [BrowserTab], selected: UUID?) {
        let ids = Set(tabs.map(\.id))

        for (id, view) in itemViews where !ids.contains(id) {
            view.removeFromSuperview()
            itemViews.removeValue(forKey: id)
        }

        for tab in tabs {
            let view: TabItemView
            if let existing = itemViews[tab.id] {
                view = existing
            } else {
                view = TabItemView()
                view.onSelect = { [weak self] in self?.onSelect?(tab.id) }
                view.onClose = { [weak self] in self?.onClose?(tab.id) }
                tabContainer.addSubview(view)
                itemViews[tab.id] = view
            }
            view.title = tab.title
            view.isSelected = tab.id == selected
            view.identityColor = Palette.color(for: tab.identity.color)
            view.favicon = tab.favicon
        }

        let selectionChanged = self.selected != selected
        order = tabs.map(\.id)
        self.selected = selected
        needsLayout = true

        if selectionChanged, let selected {
            // A tab selected by ⌘1–9 or by closing its neighbour may be scrolled out of
            // sight, and a selected tab you cannot see is indistinguishable from no tab.
            DispatchQueue.main.async { [weak self] in self?.scrollToTab(selected) }
        }
    }

    override func layout() {
        super.layout()

        let available = max(0, bounds.width - newTabButtonWidth)
        let count = CGFloat(order.count)
        let height = bounds.height - 1

        let width: CGFloat = count > 0
            ? min(maxTabWidth, max(compactTabWidth, available / count))
            : 0
        let total = width * count

        scrollView.frame = NSRect(x: 0, y: 0, width: available, height: height)
        newTabButton.frame = NSRect(x: available, y: 0, width: newTabButtonWidth, height: height)

        // The identity is at least as wide as the visible area, so a short list does not
        // scroll and a long one does.
        tabContainer.frame = NSRect(x: 0, y: 0, width: max(total, available), height: height)

        var x: CGFloat = 0
        for id in order {
            guard let view = itemViews[id] else { continue }
            view.frame = NSRect(x: x, y: 0, width: width, height: height)
            // Below the width where a title is legible, the tab shows its icon and its
            // identity colour and nothing else.
            view.isCompact = width < 118
            x += width
        }
    }

    /// Brings a tab into view, scrolling the least distance that does so.
    private func scrollToTab(_ id: UUID) {
        guard let view = itemViews[id] else { return }
        let visible = scrollView.contentView.bounds
        let frame = view.frame
        guard frame.width > 0, visible.width > 0 else { return }

        var origin = visible.origin
        if frame.minX < visible.minX {
            origin.x = frame.minX
        } else if frame.maxX > visible.maxX {
            origin.x = frame.maxX - visible.width
        } else {
            return
        }
        scrollView.contentView.scroll(to: origin)
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }
}

/// A view whose origin is top-left, so tab frames read the way they are written.
@MainActor
private final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}
