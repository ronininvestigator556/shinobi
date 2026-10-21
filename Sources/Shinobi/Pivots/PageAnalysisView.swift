// SPDX-License-Identifier: GPL-3.0-or-later
import ShinobiKit
import PivotKit
import SwiftUI

/// What the current page contains and appears to be built on.
struct PageAnalysisView: View {

    enum Tab: String, CaseIterable, Identifiable {
        case links = "Links"
        case addresses = "Addresses"
        case technologies = "Technology"
        case archives = "Archives"
        var id: String { rawValue }
    }

    let analysis: PageAnalysis
    let archives: ArchiveLookup.Result?
    let onOpen: (URL) -> Void
    let onSaveToArchive: () -> Void
    let onCopy: (String) -> Void
    let onClose: () -> Void

    @State private var tab: Tab = .links

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $tab) {
                ForEach(Tab.allCases) { Text(label(for: $0)).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(12)

            Divider()
            content
            Divider()

            HStack {
                Button("Copy list") { onCopy(copyText) }
                Spacer()
                Button("Done", action: onClose).keyboardShortcut(.cancelAction)
            }
            .padding(12)
        }
        .frame(width: 760, height: 580)
    }

    private func label(for tab: Tab) -> String {
        switch tab {
        case .links: "Links (\(analysis.links.count))"
        case .addresses: "Addresses (\(analysis.emails.count))"
        case .technologies: "Technology (\(analysis.technologies.count))"
        case .archives: "Archives"
        }
    }

    @ViewBuilder
    private var content: some View {
        switch tab {
        case .links: linksList
        case .addresses: addressesList
        case .technologies: technologiesList
        case .archives: archivesList
        }
    }

    @ViewBuilder
    private var linksList: some View {
        if analysis.links.isEmpty {
            empty("No links on this page.")
        } else {
            List {
                // Grouped by host, because "who does this site point at" is usually the
                // question, and a flat list of two hundred links does not answer it.
                ForEach(analysis.linksByHost, id: \.host) { group in
                    Section("\(group.host) — \(group.links.count)") {
                        ForEach(group.links, id: \.url) { link in
                            row(title: link.text.isEmpty ? link.url : link.text,
                                detail: link.url) { open(link.url) }
                        }
                    }
                }
                let internalLinks = analysis.links.filter { !$0.isExternal }
                if !internalLinks.isEmpty {
                    Section("Same site — \(internalLinks.count)") {
                        ForEach(internalLinks, id: \.url) { link in
                            row(title: link.text.isEmpty ? link.url : link.text,
                                detail: link.url) { open(link.url) }
                        }
                    }
                }
            }
            .listStyle(.inset)
        }
    }

    @ViewBuilder
    private var addressesList: some View {
        if analysis.emails.isEmpty {
            empty("No email addresses on this page.")
        } else {
            List(analysis.emails, id: \.self) { address in
                HStack {
                    Text(address).font(.system(size: 12, design: .monospaced)).textSelection(.enabled)
                    Spacer()
                    Button("Copy") { onCopy(address) }.buttonStyle(.link)
                }
            }
            .listStyle(.inset)
        }
    }

    @ViewBuilder
    private var technologiesList: some View {
        List {
            if analysis.technologies.isEmpty {
                Text("Nothing recognised. That is a real answer rather than a failure — a "
                     + "hand-built page often matches nothing.")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            } else {
                ForEach(Dictionary(grouping: analysis.technologies, by: \.category)
                    .sorted { $0.key < $1.key }, id: \.key) { category, items in
                    Section(category) {
                        ForEach(items, id: \.name) { technology in
                            VStack(alignment: .leading, spacing: 1) {
                                Text(technology.name).font(.system(size: 12, weight: .medium))
                                // The evidence travels with the claim: a fingerprint is an
                                // inference, and an investigator should be able to judge it.
                                Text(technology.evidence)
                                    .font(.system(size: 11)).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }

            if !analysis.headers.isEmpty {
                Section("Response headers") {
                    ForEach(analysis.headers.sorted(by: { $0.key < $1.key }), id: \.key) { name, value in
                        HStack(alignment: .top) {
                            Text(name).font(.system(size: 11)).foregroundStyle(.secondary)
                                .frame(width: 190, alignment: .leading)
                            Text(value).font(.system(size: 11, design: .monospaced))
                                .textSelection(.enabled)
                        }
                    }
                }
            }

            if !analysis.externalHosts.isEmpty {
                Section("Loads from or links to (\(analysis.externalHosts.count))") {
                    ForEach(analysis.externalHosts, id: \.self) { host in
                        Text(host).font(.system(size: 12, design: .monospaced))
                    }
                }
            }
        }
        .listStyle(.inset)
    }

    @ViewBuilder
    private var archivesList: some View {
        List {
            Section("Wayback Machine") {
                if let snapshot = archives?.wayback {
                    row(title: "Most recent capture — \(snapshot.displayDate)",
                        detail: snapshot.url) { open(snapshot.url) }
                } else if archives == nil {
                    Text("Checking…").font(.system(size: 12)).foregroundStyle(.secondary)
                } else {
                    Text("No capture found. The page may never have been archived.")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                }
            }

            Section("Look elsewhere") {
                ForEach(archives?.unqueried ?? [], id: \.service) { service in
                    row(title: service.service, detail: service.url) { open(service.url) }
                }
            }

            Section("Archive this page") {
                VStack(alignment: .leading, spacing: 6) {
                    Button("Save to the Wayback Machine…", action: onSaveToArchive)
                    // Stated before the click, not after: this is the one action in this
                    // panel that changes something outside the investigation.
                    Text("This asks the Internet Archive to fetch the page. The capture is "
                         + "public and permanent, so archiving a subject's page can reveal to "
                         + "anyone that someone was looking at it.")
                        .font(.system(size: 11))
                        .foregroundStyle(Color(Palette.statusWarn))
                }
            }
        }
        .listStyle(.inset)
    }

    private func row(title: String, detail: String, open: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title).font(.system(size: 12)).lineLimit(1)
            Text(detail).font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary).lineLimit(1)
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2, perform: open)
    }

    private func empty(_ message: String) -> some View {
        VStack {
            Spacer()
            Text(message).font(.system(size: 12)).foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private func open(_ raw: String) {
        if let url = URL(string: raw) { onOpen(url) }
    }

    private var copyText: String {
        switch tab {
        case .links: analysis.links.map(\.url).joined(separator: "\n")
        case .addresses: analysis.emails.joined(separator: "\n")
        case .technologies: analysis.technologies.map { "\($0.category): \($0.name) — \($0.evidence)" }
            .joined(separator: "\n")
        case .archives: (archives?.unqueried.map(\.url) ?? []).joined(separator: "\n")
        }
    }
}
