// SPDX-License-Identifier: GPL-3.0-or-later
import AppKit
import BookmarkKit
import Testing
@testable import Shinobi

/// Types into a real `AddressField`, through a real field editor, and checks that what comes
/// out is what went in.
///
/// The regression this guards was reported as "I can't type anything without an https:// taking
/// over". Driving AppKit's field completion meant the first bookmark match was inserted into the
/// field and left selected, so the third character replaced the first two and the address bar
/// could not be used at all. Asserting on the matcher would not have caught it — the matcher was
/// correct. The damage was done by what the view did with the matches.
@MainActor
@Suite("Address field typing")
struct AddressFieldTypingTests {

    /// Bookmarks chosen to match early and aggressively: every one of them is a candidate after
    /// a couple of characters, which is exactly the situation that broke the field.
    private static let library: [Bookmark] = [
        Bookmark(title: "DuckDuckGo", url: "https://duckduckgo.com/?q={query}",
                 folder: "Search", keyword: "ddg"),
        Bookmark(title: "Whois Lookup", url: "https://who.is/whois/{query}",
                 folder: "Domains & Infrastructure", keyword: "whois"),
        Bookmark(title: "Wayback Machine", url: "https://web.archive.org/web/*/{query}",
                 folder: "Archives", keyword: "wb"),
    ]

    /// A field wired the way the browser window wires it, in an off-screen window so that it
    /// has a field editor to type into.
    private func makeField() -> (AddressField, NSWindow) {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 200),
                              styleMask: [.titled], backing: .buffered, defer: false)
        let field = AddressField(frame: NSRect(x: 0, y: 0, width: 400, height: 22))
        field.completionSource = { typed in
            BookmarkMatcher.matches(for: typed, in: Self.library)
        }
        window.contentView?.addSubview(field)
        field.focus()
        return (field, window)
    }

    /// Types one character at a time, the way a person does.
    private func type(_ text: String, into field: AddressField) {
        guard let editor = field.fieldEditorForTesting else {
            Issue.record("the field never got a field editor")
            return
        }
        for character in text {
            editor.insertText(String(character), replacementRange: editor.selectedRange())
        }
    }

    @Test("typing a search phrase leaves the phrase alone")
    func doesNotRewritePlainTyping() {
        let (field, window) = makeField()
        defer { window.close() }

        // "wh" matches Whois on any reasonable ranking, and "who owns…" is ordinary prose an
        // investigator would expect to become a search.
        type("who owns this house", into: field)

        #expect(field.currentTextForTesting == "who owns this house")
    }

    @Test("a prefix of a bookmark is still only what was typed")
    func doesNotCompleteInline() {
        let (field, window) = makeField()
        defer { window.close() }

        type("duck", into: field)

        // The old behaviour turned this into "https://duckduckgo.com/?q={query}".
        #expect(field.currentTextForTesting == "duck")
        #expect(!field.currentTextForTesting.contains("https://"))
    }

    @Test("nothing is selected in the field after typing")
    func leavesNoSelectionToOverwrite() {
        let (field, window) = makeField()
        defer { window.close() }

        type("ddg", into: field)

        // Inline completion works by selecting the inserted remainder. A non-empty selection
        // after typing means the next keystroke would delete something the user typed.
        let editor = field.fieldEditorForTesting
        #expect(editor?.selectedRange().length == 0)
    }

    @Test("Return submits the typed text when no suggestion is highlighted")
    func returnSubmitsWhatWasTyped() {
        let (field, window) = makeField()
        defer { window.close() }

        var submitted: String?
        field.onSubmit = { submitted = $0 }
        var chosen: BookmarkMatcher.Match?
        field.onChooseSuggestion = { chosen = $0 }

        type("wayback of a council page", into: field)
        // What the field editor does with Return: offer it to the delegate first.
        field.fieldEditorForTesting?.doCommand(by: #selector(NSResponder.insertNewline(_:)))

        #expect(submitted == "wayback of a council page")
        #expect(chosen == nil, "a suggestion was taken without being highlighted")
    }
}
