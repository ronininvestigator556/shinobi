// SPDX-License-Identifier: GPL-3.0-or-later
import IdentityKit
import MonitorKit
import ShinobiKit
import SwiftUI

/// The watch list.
struct WatchListView: View {

    let watches: [Watch]
    let containerName: (UUID) -> String
    let onToggle: (Watch) -> Void
    let onCheckNow: (Watch) -> Void
    let onOpen: (Watch) -> Void
    let onRemove: (Watch) -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if watches.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    Text("Nothing is being watched")
                        .font(.system(size: 13, weight: .medium))
                    Text("Open a page and choose Page ▸ Watch This Page to start.")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                List(watches) { watch in
                    HStack(alignment: .top, spacing: 10) {
                        Circle()
                            .fill(colour(for: watch))
                            .frame(width: 8, height: 8)
                            .padding(.top, 4)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(watch.name)
                                .font(.system(size: 13, weight: .medium))
                            Text(watch.url)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.tertiary).lineLimit(1)
                            Text("\(containerName(watch.containerID)) · \(watch.interval.displayName) · \(watch.sensitivity.displayName)")
                                .font(.system(size: 11)).foregroundStyle(.secondary)
                            Text(watch.statusLine)
                                .font(.system(size: 11))
                                .foregroundStyle(statusColour(for: watch))
                        }

                        Spacer()

                        VStack(alignment: .trailing, spacing: 4) {
                            Button(watch.isEnabled ? "Pause" : "Resume") { onToggle(watch) }
                                .buttonStyle(.link)
                            Button("Check now") { onCheckNow(watch) }.buttonStyle(.link)
                            Button("Open") { onOpen(watch) }.buttonStyle(.link)
                            Button("Remove", role: .destructive) { onRemove(watch) }
                                .buttonStyle(.link)
                        }
                        .font(.system(size: 11))
                    }
                    .padding(.vertical, 4)
                }
                .listStyle(.inset)
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                // Said here rather than buried in documentation, because it is the part of
                // monitoring that can cost an investigator the case.
                Text("Checks load the page as the identity you chose, on a jittered schedule. "
                     + "Repeatedly fetching a subject's page is still a pattern in their logs, "
                     + "and a page that only a watcher would revisit hourly can give away that "
                     + "somebody is watching.")
                    .font(.system(size: 11))
                    .foregroundStyle(Color(Palette.statusWarn))
                HStack {
                    Spacer()
                    Button("Done", action: onClose).keyboardShortcut(.cancelAction)
                }
            }
            .padding(12)
        }
        .frame(width: 720, height: 520)
    }

    private func colour(for watch: Watch) -> Color {
        if !watch.isEnabled { return Color(Palette.textTertiary) }
        if watch.consecutiveFailures > 0 { return Color(Palette.statusAlert) }
        if watch.lastChangedAt != nil { return Color(Palette.statusWarn) }
        return Color(Palette.statusCapture)
    }

    private func statusColour(for watch: Watch) -> Color {
        if watch.consecutiveFailures > 0 { return Color(Palette.statusAlert) }
        if watch.lastChangedAt != nil { return Color(Palette.statusWarn) }
        return .secondary
    }
}

/// The sheet for setting a watch up.
struct WatchEditorView: View {

    @State var name: String
    @State var interval: Watch.Interval
    @State var sensitivity: ChangeDetector.Sensitivity
    @State var recordToCase: Bool

    let url: String
    let containerName: String
    let caseName: String?
    let onAdd: (String, Watch.Interval, ChangeDetector.Sensitivity, Bool) -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Form {
                Section("Watch") {
                    TextField("Name", text: $name)
                    LabeledContent("Address") {
                        Text(url).font(.system(size: 11, design: .monospaced)).lineLimit(2)
                    }
                    LabeledContent("Checked as") { Text(containerName) }
                }

                Section("How often") {
                    Picker("Interval", selection: $interval) {
                        ForEach(Watch.Interval.allCases, id: \.self) {
                            Text($0.displayName).tag($0)
                        }
                    }
                    Text("Checks are spread by up to a fifth of the interval, so they do not "
                         + "land at the same moment every time.")
                        .font(.caption).foregroundStyle(.secondary)
                }

                Section("What counts as a change") {
                    Picker("Sensitivity", selection: $sensitivity) {
                        ForEach(ChangeDetector.Sensitivity.allCases, id: \.self) {
                            Text($0.displayName).tag($0)
                        }
                    }
                    Text(sensitivity.explanation)
                        .font(.caption).foregroundStyle(.secondary)
                }

                Section("When it changes") {
                    if let caseName {
                        Toggle("Capture into \(caseName)", isOn: $recordToCase)
                        Text("The changed page is archived and screenshotted at the moment the "
                             + "change is noticed, with the difference recorded as a note.")
                            .font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text("No case is open, so changes will only be notified. Open a case "
                             + "before adding a watch if you want changes preserved.")
                            .font(.caption).foregroundStyle(Color(Palette.statusWarn))
                    }
                }
            }
            .formStyle(.grouped)

            Divider()
            HStack {
                Spacer()
                Button("Cancel", role: .cancel, action: onCancel).keyboardShortcut(.cancelAction)
                Button("Watch") { onAdd(name, interval, sensitivity, recordToCase) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(12)
        }
        .frame(width: 480, height: 520)
    }
}
