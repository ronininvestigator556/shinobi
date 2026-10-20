// SPDX-License-Identifier: GPL-3.0-or-later
import AppKit
import ShinobiKit

/// Find-on-page.
///
/// Table stakes for reading long documents, and disproportionately useful in this tool
/// specifically: a great deal of OSINT is scanning a long page — a filing, a forum thread,
/// a member list — for one name.
@MainActor
final class FindBarView: NSView {

    static let barHeight: CGFloat = 34

    private let field = NSTextField()
    private let resultLabel = NSTextField(labelWithString: "")
    private let previousButton = NSButton()
    private let nextButton = NSButton()
    private let closeButton = NSButton()

    /// Called as the query changes, and again for each next/previous step.
    /// `forward` is nil for a fresh search.
    var onSearch: ((String, Bool?) -> Void)?
    var onDismiss: (() -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = Palette.panelBackground.cgColor
        build()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func build() {
        field.placeholderString = "Find on page"
        field.font = Typography.body
        field.textColor = Palette.textPrimary
        field.drawsBackground = true
        field.backgroundColor = Palette.wellBackground
        field.isBordered = false
        field.focusRingType = .none
        field.delegate = self
        field.target = self
        field.action = #selector(findNext)
        field.wantsLayer = true
        field.layer?.cornerRadius = Typography.cornerRadius
        field.layer?.borderWidth = 1
        field.layer?.borderColor = Palette.separator.cgColor

        resultLabel.font = Typography.caption
        resultLabel.textColor = Palette.textSecondary
        resultLabel.alignment = .right

        configure(previousButton, symbol: "chevron.up", action: #selector(findPrevious), tooltip: "Previous match (⇧⌘G)")
        configure(nextButton, symbol: "chevron.down", action: #selector(findNext), tooltip: "Next match (⌘G)")
        configure(closeButton, symbol: "xmark", action: #selector(dismiss), tooltip: "Done (⎋)")

        let stack = NSStackView(views: [field, resultLabel, previousButton, nextButton, closeButton])
        stack.orientation = .horizontal
        stack.spacing = 8
        stack.alignment = .centerY
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Typography.contentInset),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Typography.contentInset),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            field.widthAnchor.constraint(equalToConstant: 260),
            field.heightAnchor.constraint(equalToConstant: 22),
            resultLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 90),
        ])
    }

    private func configure(_ button: NSButton, symbol: String, action: Selector, tooltip: String) {
        button.isBordered = false
        button.bezelStyle = .inline
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: tooltip)?
            .withSymbolConfiguration(.init(pointSize: 11, weight: .medium))
        button.contentTintColor = Palette.textSecondary
        button.target = self
        button.action = action
        button.toolTip = tooltip
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        Palette.separator.setFill()
        NSRect(x: 0, y: bounds.maxY - 1, width: bounds.width, height: 1).fill()
    }

    // MARK: Actions

    @objc private func findNext() { onSearch?(field.stringValue, true) }
    @objc private func findPrevious() { onSearch?(field.stringValue, false) }
    @objc private func dismiss() { onDismiss?() }

    /// Escape dismisses, matching every other find bar on the platform.
    override func cancelOperation(_ sender: Any?) { onDismiss?() }

    // MARK: State

    func focus() {
        window?.makeFirstResponder(field)
        field.currentEditor()?.selectAll(nil)
    }

    /// Advances the search, used by ⌘G / ⇧⌘G when focus is in the page rather than the field.
    func step(forward: Bool) {
        onSearch?(field.stringValue, forward)
    }

    func showResult(matched: Bool) {
        let query = field.stringValue
        if query.isEmpty {
            resultLabel.stringValue = ""
        } else if matched {
            resultLabel.stringValue = "Found"
            resultLabel.textColor = Palette.textSecondary
        } else {
            resultLabel.stringValue = "Not found"
            resultLabel.textColor = Palette.statusWarn
        }
        [previousButton, nextButton].forEach { $0.isEnabled = !query.isEmpty }
    }
}

extension FindBarView: NSTextFieldDelegate {
    /// Search as the user types, so the first match is highlighted without a round trip
    /// through the return key.
    func controlTextDidChange(_ notification: Notification) {
        onSearch?(field.stringValue, nil)
    }
}
