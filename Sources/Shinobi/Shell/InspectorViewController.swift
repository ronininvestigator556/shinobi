// SPDX-License-Identifier: GPL-3.0-or-later
import AppKit
import CaseKit
import ShinobiKit
import PivotKit

/// The right-hand inspector: what is known about the page currently on screen.
///
/// Fields that Shinobi cannot yet answer show an em dash and a one-line explanation rather
/// than a plausible placeholder value. In a tool whose output is meant to be defensible,
/// an interface that displays a fabricated hash — even in a screenshot, even in
/// development — is a liability.
@MainActor
final class InspectorViewController: NSViewController {

    private let stack = NSStackView()
    private var rowsBySection: [String: [InspectorRow]] = [:]

    private let urlRow = InspectorRow(label: "URL", mono: true)
    private let titleRow = InspectorRow(label: "Title", mono: false)
    private let transportRow = InspectorRow(label: "Transport", mono: true)
    private let capturedRow = InspectorRow(label: "Captured", mono: true)
    private let hashRow = InspectorRow(label: "SHA-256", mono: true)
    private let entitiesHeader = InspectorSectionHeader(title: "Entities")
    private let entitiesNote = InspectorNote(text: "Nothing recognised on this page.")
    private var artifactRows: [InspectorRow] = []
    private var entityRows: [NSView] = []

    override func loadView() {
        view = NSView()
        view.wantsLayer = true
        view.setLayerBackground(Palette.panelBackground)

        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 0
        stack.edgeInsets = NSEdgeInsets(top: 6, left: 0, bottom: 6, right: 0)
        stack.translatesAutoresizingMaskIntoConstraints = false

        stack.addArrangedSubview(InspectorSectionHeader(title: "Page"))
        [urlRow, titleRow, transportRow].forEach(stack.addArrangedSubview)

        stack.addArrangedSubview(InspectorSectionHeader(title: "Evidence"))
        [capturedRow, hashRow].forEach(stack.addArrangedSubview)

        stack.addArrangedSubview(entitiesHeader)
        stack.addArrangedSubview(entitiesNote)

        let scrollView = NSScrollView()
        scrollView.contentView = FlippedClipView()
        scrollView.documentView = stack
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            stack.widthAnchor.constraint(equalTo: scrollView.widthAnchor),
            stack.topAnchor.constraint(equalTo: scrollView.contentView.topAnchor),
        ])

        // Hairline separating the inspector from the web content.
        let divider = NSBox()
        divider.boxType = .custom
        divider.borderWidth = 0
        divider.fillColor = Palette.separator
        divider.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(divider)
        NSLayoutConstraint.activate([
            divider.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            divider.topAnchor.constraint(equalTo: view.topAnchor),
            divider.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            divider.widthAnchor.constraint(equalToConstant: 1),
        ])

        showEmptyState()
    }

    // MARK: Updates

    func update(
        for tab: BrowserTab?,
        caseIsOpen: Bool = false,
        recordedDigest: String? = nil,
        artifacts: [Artifact] = []
    ) {
        guard let tab, let url = tab.url else {
            showEmptyState()
            return
        }

        urlRow.value = url.absoluteString
        titleRow.value = tab.title

        if tab.isSecure {
            transportRow.value = "HTTPS"
            transportRow.valueColor = Palette.textPrimary
        } else {
            transportRow.value = "HTTP — not encrypted"
            transportRow.valueColor = Palette.statusWarn
        }

        showArtifacts(artifacts)

        if caseIsOpen {
            // Deliberately labelled as the page *text*, not as a capture of the page.
            // Screenshots, PDF and a replayable archive arrive with the capture pipeline;
            // calling this a capture now would overstate what the case file holds.
            if let recordedDigest {
                capturedRow.value = "Page text recorded"
                capturedRow.detail = nil
                hashRow.value = recordedDigest
                hashRow.detail = "SHA-256 of the recorded page text"
            } else {
                capturedRow.value = "Recording…"
                capturedRow.detail = "Waiting for the page to finish"
                hashRow.value = "—"
                hashRow.detail = nil
            }
        } else {
            capturedRow.value = "—"
            capturedRow.detail = "No case open"
            hashRow.value = "—"
            hashRow.detail = "No artifact to hash"
        }
    }

    /// Lists what was actually preserved for this page, with each artifact's own digest.
    ///
    /// Shown as a list rather than a single "captured" flag because the artifacts are not
    /// interchangeable and capture is not all-or-nothing: navigating away mid-capture leaves
    /// some taken and some not, and an investigator needs to see which.
    private func showArtifacts(_ artifacts: [Artifact]) {
        for row in artifactRows { row.removeFromSuperview() }
        artifactRows.removeAll()

        guard !artifacts.isEmpty else { return }
        guard let index = stack.arrangedSubviews.firstIndex(where: { $0 === entitiesHeader }) else { return }

        for artifact in artifacts.reversed() {
            let row = InspectorRow(label: artifact.artifactKind?.displayName ?? artifact.kind, mono: true)
            row.value = artifact.digest
            row.detail = [ByteCountFormatter.string(fromByteCount: Int64(artifact.byteCount), countStyle: .file),
                          artifact.note].compactMap { $0 }.joined(separator: " · ")
            stack.insertArrangedSubview(row, at: index)
            artifactRows.append(row)
        }
    }

    /// Lists people, organisations and places found on the page.
    ///
    /// Produced by a deterministic tagger rather than a language model: a model asked for the
    /// people on a page will occasionally name one who is not there, and a fabricated name in
    /// an investigation is worse than a missing one because it is actionable.
    func showEntities(_ mentions: [NamedEntities.Mention]) {
        for row in entityRows { row.removeFromSuperview() }
        entityRows.removeAll()

        entitiesNote.isHidden = !mentions.isEmpty
        guard !mentions.isEmpty else { return }

        for group in NamedEntities.grouped(mentions) {
            let row = InspectorRow(label: group.kind.displayName, mono: false)
            row.value = group.mentions
                .map { $0.count > 1 ? "\($0.name) (\($0.count))" : $0.name }
                .joined(separator: ", ")
            row.wrapsValue = true
            stack.addArrangedSubview(row)
            entityRows.append(row)
        }
    }

    private func showEmptyState() {
        urlRow.value = "—"
        titleRow.value = "—"
        transportRow.value = "—"
        transportRow.valueColor = Palette.textSecondary
        capturedRow.value = "—"
        capturedRow.detail = "No case open"
        hashRow.value = "—"
        hashRow.detail = "No artifact to hash"
    }
}

// MARK: - Components

/// A section heading inside the inspector.
@MainActor
final class InspectorSectionHeader: NSView {

    private let title: String

    init(title: String) {
        self.title = title
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: 26).isActive = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let attributed = NSAttributedString(string: title.uppercased(), attributes: [
            .font: Typography.sectionHeader,
            .foregroundColor: Palette.textTertiary,
            .kern: Typography.sectionHeaderTracking,
        ])
        let size = attributed.size()
        attributed.draw(at: NSPoint(
            x: Typography.contentInset + 1,
            y: bounds.maxY - size.height - 4
        ))

        Palette.separator.setFill()
        NSRect(x: 0, y: bounds.maxY - 1, width: bounds.width, height: 1).fill()
    }
}

/// A label / value pair. Values that are evidence are set in mono and are selectable, so a
/// hash or URL can be copied straight out of the panel.
@MainActor
final class InspectorRow: NSView {

    private let labelField = NSTextField(labelWithString: "")
    private let valueField = NSTextField(labelWithString: "")
    private let detailField = NSTextField(labelWithString: "")

    var value: String = "—" {
        didSet {
            valueField.stringValue = value
            toolTip = value == "—" ? nil : value
        }
    }

    var valueColor: NSColor = Palette.textPrimary {
        didSet { valueField.textColor = valueColor }
    }

    /// Entity lists are long and worth reading in full, unlike a URL or a digest.
    var wrapsValue: Bool = false {
        didSet {
            valueField.lineBreakMode = wrapsValue ? .byWordWrapping : .byTruncatingMiddle
            valueField.maximumNumberOfLines = wrapsValue ? 6 : 1
            valueField.preferredMaxLayoutWidth = wrapsValue ? 240 : 0
        }
    }

    /// Optional sub-line explaining why a value is absent.
    var detail: String? {
        didSet {
            detailField.stringValue = detail ?? ""
            detailField.isHidden = detail == nil
        }
    }

    init(label: String, mono: Bool) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        labelField.stringValue = label
        labelField.font = Typography.caption
        labelField.textColor = Palette.textSecondary

        valueField.font = mono ? Typography.mono : Typography.body
        valueField.textColor = Palette.textPrimary
        valueField.lineBreakMode = .byTruncatingMiddle   // keep scheme+host and the tail visible
        valueField.isSelectable = true
        valueField.allowsEditingTextAttributes = false

        detailField.font = Typography.caption
        detailField.textColor = Palette.textTertiary
        detailField.isHidden = true

        let stack = NSStackView(views: [labelField, valueField, detailField])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 1
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Typography.contentInset + 1),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Typography.contentInset),
        ])

        value = "—"
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

/// An explanatory line for a section that has nothing to show yet.
@MainActor
final class InspectorNote: NSView {

    init(text: String) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        let field = NSTextField(wrappingLabelWithString: text)
        field.font = Typography.caption
        field.textColor = Palette.textTertiary
        field.translatesAutoresizingMaskIntoConstraints = false
        addSubview(field)

        NSLayoutConstraint.activate([
            field.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            field.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6),
            field.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Typography.contentInset + 1),
            field.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Typography.contentInset),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}


/// A clip view with a top-left origin.
///
/// `NSScrollView` lays its document view out from the bottom by default, which puts a
/// short stack against the bottom of the panel. Flipping the clip view makes the inspector
/// fill from the top, matching the sidebar and every other list in the interface.
@MainActor
final class FlippedClipView: NSClipView {
    override var isFlipped: Bool { true }
}
