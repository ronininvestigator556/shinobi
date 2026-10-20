// SPDX-License-Identifier: GPL-3.0-or-later
import AppKit
import BookmarkKit
import ShinobiKit

/// The address field.
///
/// Set in mono, like every other address in the interface — what is in this field usually
/// ends up in a report. It also carries the transport indicator, because "was this page
/// served over TLS" is a question that gets asked of exhibits.
@MainActor
final class AddressField: NSView {

    static let fieldHeight: CGFloat = 22

    /// Supplies bookmark matches for what has been typed so far.
    var completionSource: ((String) -> [BookmarkMatcher.Match])?

    /// Called when the investigator picks a bookmark out of the suggestions list.
    var onChooseSuggestion: ((BookmarkMatcher.Match) -> Void)?

    private let suggestions = SuggestionsPanel()

    /// Whether the user has typed since the field was last set programmatically.
    ///
    /// Focus alone is not enough to decide this. Every new tab focuses the address field
    /// while it is still empty, and a focus-only guard means the first navigation in a tab
    /// never reaches the field.
    private var hasUncommittedEdit = false

    private let textField = NSTextField()
    private let lockView = NSImageView()

    /// Called when the user commits an entry.
    var onSubmit: ((String) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        // The toolbar sizes this item from its constraints, which requires opting out of
        // autoresizing translation on the item view itself.
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.backgroundColor = Palette.wellBackground.cgColor
        layer?.cornerRadius = Typography.cornerRadius
        layer?.borderWidth = 1
        layer?.borderColor = Palette.separator.cgColor

        lockView.imageScaling = .scaleProportionallyDown
        lockView.translatesAutoresizingMaskIntoConstraints = false

        textField.isBordered = false
        textField.drawsBackground = false
        textField.focusRingType = .none
        textField.font = Typography.mono
        textField.textColor = Palette.textPrimary
        textField.placeholderString = "Search or enter address"
        textField.lineBreakMode = .byTruncatingTail
        textField.cell?.usesSingleLineMode = true
        textField.delegate = self
        // Long addresses scroll within the field while being edited rather than being
        // truncated out from under the insertion point.
        (textField.cell as? NSTextFieldCell)?.isScrollable = true
        textField.target = self
        textField.action = #selector(submit)
        textField.translatesAutoresizingMaskIntoConstraints = false
        addSubview(lockView)
        addSubview(textField)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: Self.fieldHeight),

            lockView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 7),
            lockView.centerYAnchor.constraint(equalTo: centerYAnchor),
            lockView.widthAnchor.constraint(equalToConstant: 11),
            lockView.heightAnchor.constraint(equalToConstant: 11),

            textField.leadingAnchor.constraint(equalTo: lockView.trailingAnchor, constant: 6),
            textField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -7),
            textField.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])

        suggestions.onChoose = { [weak self] match in self?.commit(match) }

        setTransport(nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    @objc private func submit() {
        let value = textField.stringValue
        suggestions.hide()
        guard !value.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        hasUncommittedEdit = false
        onSubmit?(value)
        // Hand focus back to the page so typing continues in the content, not the chrome.
        window?.makeFirstResponder(nil)
    }

    // MARK: State

    /// Updates the displayed address, unless the user is mid-edit — clobbering a
    /// half-typed address because a background frame finished loading is infuriating.
    func setAddress(_ url: URL?, isSecure: Bool) {
        if !hasUncommittedEdit {
            textField.stringValue = url?.absoluteString ?? ""
        }
        setTransport(url == nil ? nil : isSecure)
    }

    private func setTransport(_ isSecure: Bool?) {
        switch isSecure {
        case .none:
            lockView.image = NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: nil)
            lockView.contentTintColor = Palette.textTertiary
            lockView.toolTip = nil
        case .some(true):
            lockView.image = NSImage(systemSymbolName: "lock.fill", accessibilityDescription: "Encrypted")
            lockView.contentTintColor = Palette.textSecondary
            lockView.toolTip = "Served over HTTPS"
        case .some(false):
            lockView.image = NSImage(
                systemSymbolName: "exclamationmark.triangle.fill",
                accessibilityDescription: "Not encrypted"
            )
            lockView.contentTintColor = Palette.statusWarn
            lockView.toolTip = "Served over HTTP — contents were transmitted in the clear"
        }
    }

    func focus() {
        window?.makeFirstResponder(textField)
        textField.currentEditor()?.selectAll(nil)
    }

    // MARK: Test access
    //
    // The address bar is only meaningfully testable through a live field editor: the regression
    // it guards against was AppKit rewriting the text, which no amount of testing the matcher
    // would have shown.

    var fieldEditorForTesting: NSTextView? { textField.currentEditor() as? NSTextView }
    var currentTextForTesting: String { fieldEditorForTesting?.string ?? textField.stringValue }
}

extension AddressField: NSTextFieldDelegate {

    /// Offers bookmark matches as the investigator types.
    ///
    /// The suggestions are shown in a list and nothing is inserted into the field. An earlier
    /// version drove AppKit's own field completion, which inserts the match inline — typing two
    /// characters replaced the line with a bookmark's `https://…` and made the field unusable.
    /// What has been typed is the investigator's, and is never rewritten by a guess.
    func controlTextDidChange(_ notification: Notification) {
        hasUncommittedEdit = true
        let typed = textField.stringValue
        suggestions.show(completionSource?(typed) ?? [], below: self)
    }

    /// Arrow keys move through the list; Return takes a highlighted suggestion, if there is one.
    func control(_ control: NSControl, textView: NSTextView,
                 doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.moveDown(_:)):
            return suggestions.moveSelection(by: 1)
        case #selector(NSResponder.moveUp(_:)):
            return suggestions.moveSelection(by: -1)
        case #selector(NSResponder.cancelOperation(_:)):
            // First Escape dismisses the list, leaving the typing intact; a second one is left
            // to the field's usual behaviour.
            if suggestions.isVisible {
                suggestions.hide()
                return true
            }
            return false
        case #selector(NSResponder.insertNewline(_:)):
            // Only when something is actually highlighted. Otherwise Return submits what was
            // typed, so prose still becomes a search.
            guard let match = suggestions.selectedMatch else { return false }
            commit(match)
            return true
        default:
            return false
        }
    }

    /// Abandoning the field discards the edit, so the next navigation is free to write to it.
    func controlTextDidEndEditing(_ notification: Notification) {
        hasUncommittedEdit = false
        suggestions.hide()
    }
}

extension AddressField {
    /// Takes a suggestion: shows where it goes, and goes there.
    fileprivate func commit(_ match: BookmarkMatcher.Match) {
        suggestions.hide()
        hasUncommittedEdit = false
        onChooseSuggestion?(match)
        window?.makeFirstResponder(nil)
    }
}
