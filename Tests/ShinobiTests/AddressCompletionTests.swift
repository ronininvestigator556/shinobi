// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import Testing

/// Guards the address field against ever completing inline again.
///
/// This cannot be reached by a unit test — `AddressField` lives in the executable target and
/// the behaviour only appears with a live field editor — but the regression is severe enough
/// to be worth catching in the source. Driving AppKit's field completion made the address bar
/// impossible to type in: `complete(_:)` inserts the first candidate into the field and selects
/// the remainder, so with bookmark URLs as candidates, two characters became `https://…` and
/// every keystroke after that overwrote the selection.
///
/// Suggestions belong in a list the investigator chooses from, never in their typing.
@Suite("Address completion")
struct AddressCompletionTests {

    private var addressField: String {
        get throws {
            let root = URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()  // ShinobiTests
                .deletingLastPathComponent()  // Tests
                .deletingLastPathComponent()  // repo root
            return try String(
                contentsOf: root.appending(path: "Sources/Shinobi/Shell/AddressField.swift"),
                encoding: .utf8)
        }
    }

    @Test("the field editor is never asked to complete")
    func doesNotDriveFieldCompletion() throws {
        let source = try addressField
        #expect(!source.contains("complete(nil)"))
        #expect(!source.contains(".complete("))
    }

    @Test("the inline-completion delegate hook is not implemented")
    func doesNotSupplyInlineCompletions() throws {
        // Implementing this is what lets AppKit rewrite the field at all. Without it, the
        // system has nothing to insert.
        #expect(!(try addressField).contains("forPartialWordRange"))
    }

    @Test("suggestions are shown in a list instead")
    func offersASuggestionsList() throws {
        let source = try addressField
        #expect(source.contains("suggestions.show("))
        // Return only takes a suggestion when one is highlighted, so typed prose still
        // submits as a search.
        #expect(source.contains("suggestions.selectedMatch"))
    }
}
