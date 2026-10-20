// SPDX-License-Identifier: GPL-3.0-or-later
import BookmarkKit
import ShinobiKit
import SwiftUI

/// Browse, re-file and edit bookmarks.
struct BookmarkManagerView: View {

    let bookmarks: [Bookmark]
    let folders: [String]
    let onOpen: (Bookmark) -> Void
    let onUpdate: (Bookmark) -> Void
    let onRemove: (Bookmark) -> Void
    let onClose: () -> Void

    @State private var filter = ""
    @State private var selectedFolder: String?
    @State private var editing: Bookmark?

    private var visible: [Bookmark] {
        var result = bookmarks
        if let selectedFolder {
            result = result.filter { $0.folder == selectedFolder }
        }
        let query = filter.trimmingCharacters(in: .whitespaces)
        if !query.isEmpty {
            result = BookmarkMatcher.matches(for: query, in: result, limit: 500).map(\.bookmark)
        } else {
            result.sort { ($0.folder, $0.title) < ($1.folder, $1.title) }
        }
        return result
    }

    var body: some View {
        HSplitView {
            List(selection: $selectedFolder) {
                Text("All (\(bookmarks.count))").tag(String?.none)
                ForEach(folders, id: \.self) { folder in
                    let count = bookmarks.filter { $0.folder == folder }.count
                    Text("\(folder) (\(count))").tag(String?.some(folder))
                }
            }
            .frame(minWidth: 190, maxWidth: 260)

            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Filter by name, address or what it is for", text: $filter)
                        .textFieldStyle(.plain)
                }
                .padding(10)

                Divider()

                if visible.isEmpty {
                    VStack {
                        Spacer()
                        Text(bookmarks.isEmpty ? "No bookmarks yet." : "Nothing matches.")
                            .font(.system(size: 12)).foregroundStyle(.secondary)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                } else {
                    List(visible) { bookmark in
                        row(for: bookmark)
                    }
                    .listStyle(.inset)
                }
            }
            .frame(minWidth: 480)
        }
        .frame(width: 860, height: 560)
        .safeAreaInset(edge: .bottom) {
            HStack {
                Text("Double-click to open. A keyword lets you reach a bookmark by typing it "
                     + "in the address bar.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                Spacer()
                Button("Done", action: onClose).keyboardShortcut(.cancelAction)
            }
            .padding(12)
            .background(.bar)
        }
        .sheet(item: $editing) { bookmark in
            BookmarkEditorView(
                bookmark: bookmark,
                folders: folders,
                onSave: { onUpdate($0); editing = nil },
                onCancel: { editing = nil }
            )
        }
    }

    private func row(for bookmark: Bookmark) -> some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(bookmark.title).font(.system(size: 13, weight: .medium))
                    if bookmark.isSearch {
                        Text("search").font(.system(size: 10))
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Color(Palette.accent).opacity(0.2))
                            .clipShape(Capsule())
                    }
                    if bookmark.requiresAccount {
                        Text("account").font(.system(size: 10))
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Color(Palette.statusWarn).opacity(0.2))
                            .clipShape(Capsule())
                    }
                    if let keyword = bookmark.keyword {
                        Text(keyword).font(.system(size: 10, design: .monospaced))
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Color(Palette.textTertiary).opacity(0.25))
                            .clipShape(Capsule())
                    }
                }
                Text(bookmark.url).font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.tertiary).lineLimit(1)
                if let note = bookmark.note {
                    Text(note).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(2)
                }
                Text(bookmark.folder).font(.system(size: 10)).foregroundStyle(.tertiary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                Button("Edit") { editing = bookmark }.buttonStyle(.link)
                Button("Remove", role: .destructive) { onRemove(bookmark) }.buttonStyle(.link)
            }
            .font(.system(size: 11))
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { onOpen(bookmark) }
    }
}

/// Editing one bookmark.
struct BookmarkEditorView: View {

    @State var draft: Bookmark
    let folders: [String]
    let onSave: (Bookmark) -> Void
    let onCancel: () -> Void

    @State private var newFolder = ""

    init(bookmark: Bookmark, folders: [String],
         onSave: @escaping (Bookmark) -> Void, onCancel: @escaping () -> Void) {
        _draft = State(initialValue: bookmark)
        self.folders = folders
        self.onSave = onSave
        self.onCancel = onCancel
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Form {
                Section("Bookmark") {
                    TextField("Title", text: $draft.title)
                    TextField("Address", text: $draft.url, axis: .vertical).lineLimit(1...3)
                    Text("Put {query} where a search term should go, and the bookmark becomes "
                         + "a search you can run from the address bar.")
                        .font(.caption).foregroundStyle(.secondary)
                }

                Section("Filing") {
                    Picker("Folder", selection: $draft.folder) {
                        ForEach(folders, id: \.self) { Text($0).tag($0) }
                        if !folders.contains(draft.folder) {
                            Text(draft.folder).tag(draft.folder)
                        }
                    }
                    HStack {
                        TextField("New folder", text: $newFolder)
                        Button("Use") {
                            let name = newFolder.trimmingCharacters(in: .whitespaces)
                            guard !name.isEmpty else { return }
                            draft.folder = name
                            newFolder = ""
                        }
                        .disabled(newFolder.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }

                Section("Shortcuts") {
                    TextField("Keyword", text: Binding(
                        get: { draft.keyword ?? "" },
                        set: { draft.keyword = $0.isEmpty ? nil : $0.lowercased() }))
                    Text("Type the keyword in the address bar to go straight here. With a "
                         + "search bookmark, anything after it becomes the search term.")
                        .font(.caption).foregroundStyle(.secondary)

                    TextField("What it is for", text: Binding(
                        get: { draft.note ?? "" },
                        set: { draft.note = $0.isEmpty ? nil : $0 }), axis: .vertical)
                        .lineLimit(1...3)
                    Toggle("Needs an account or payment", isOn: $draft.requiresAccount)
                }
            }
            .formStyle(.grouped)

            Divider()
            HStack {
                Spacer()
                Button("Cancel", role: .cancel, action: onCancel).keyboardShortcut(.cancelAction)
                Button("Save") { onSave(draft) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(draft.title.trimmingCharacters(in: .whitespaces).isEmpty
                              || draft.url.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(12)
        }
        .frame(width: 480, height: 520)
    }
}
