// SPDX-License-Identifier: GPL-3.0-or-later
import CaseKit
import ShinobiKit
import SwiftUI

/// Full-text search across everything recorded in the open case.
///
/// The reason this exists rather than relying on browser history: history knows where you
/// went, not what was on the page. An investigator three weeks into a case remembers a
/// sentence, not a URL — "there was a filing that named the registered agent" — and this is
/// what turns that back into a source.
struct CaseSearchView: View {

    let caseName: String
    let search: (String) -> [SearchHit]
    let onOpen: (URL) -> Void
    let onClose: () -> Void

    @State private var query = ""
    @State private var hits: [SearchHit] = []
    @State private var hasSearched = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search everything recorded in \(caseName)", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .onSubmit(run)
                    .onChange(of: query) { _, _ in run() }
                if !query.isEmpty {
                    Button { query = ""; run() } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(12)

            Divider()

            if hits.isEmpty {
                VStack(spacing: 6) {
                    Spacer()
                    Text(emptyMessage)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                List(hits, id: \.visitID) { hit in
                    row(for: hit)
                        .contentShape(Rectangle())
                        .onTapGesture(count: 2) {
                            if let url = URL(string: hit.url) { onOpen(url) }
                        }
                }
                .listStyle(.inset)
            }

            Divider()

            HStack {
                if !hits.isEmpty {
                    Text("\(hits.count) result\(hits.count == 1 ? "" : "s") · double-click to open")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Done", action: onClose).keyboardShortcut(.cancelAction)
            }
            .padding(12)
        }
        .frame(width: 720, height: 520)
    }

    private var emptyMessage: String {
        if query.trimmingCharacters(in: .whitespaces).isEmpty {
            return "Type to search page text, titles and addresses."
        }
        return hasSearched ? "Nothing recorded in this case matches." : ""
    }

    @ViewBuilder
    private func row(for hit: SearchHit) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(hit.title.isEmpty ? hit.url : hit.title)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(1)

            // The snippet is why this is a search rather than a list of links: it shows the
            // words that matched, in context, so the right source is identifiable at a glance.
            Text(highlighted(hit.snippet))
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineLimit(2)

            HStack(spacing: 6) {
                Text(hit.url)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                Text("·").foregroundStyle(.tertiary)
                Text(hit.containerName)
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                Text("·").foregroundStyle(.tertiary)
                Text(hit.visited.formatted(date: .abbreviated, time: .shortened))
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 3)
    }

    /// FTS5 marks matches with sentinels rather than markup; turn them into bold runs.
    private func highlighted(_ snippet: String) -> AttributedString {
        var result = AttributedString()
        var isMatch = false
        for part in snippet.split(separator: "⟦", omittingEmptySubsequences: false) {
            for (index, piece) in part.split(separator: "⟧", omittingEmptySubsequences: false).enumerated() {
                var run = AttributedString(String(piece))
                if isMatch && index == 0 {
                    run.font = .system(size: 12, weight: .semibold)
                    run.foregroundColor = Color(Palette.accent)
                }
                result += run
            }
            isMatch = true
        }
        return result
    }

    private func run() {
        hits = search(query)
        hasSearched = true
    }
}
