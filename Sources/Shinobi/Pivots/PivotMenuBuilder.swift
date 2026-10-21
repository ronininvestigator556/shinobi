// SPDX-License-Identifier: GPL-3.0-or-later
import AppKit
import ShinobiKit
import PivotKit

/// Builds the pivot section of the context menu.
@MainActor
enum PivotMenuBuilder {

    /// Menu items for whatever was right-clicked, or an empty array when nothing is
    /// recognisable — in which case the caller adds nothing rather than an empty submenu.
    static func items(
        for target: ContextTarget,
        open: @escaping (URL) -> Void,
        inspectImage: @escaping (URL) -> Void,
        transcribeImage: @escaping (URL) -> Void
    ) -> [NSMenuItem] {
        var items: [NSMenuItem] = []

        // The candidates worth classifying, most likely first. A selection is the strongest
        // signal of intent: if someone highlighted something before right-clicking, that is
        // what they mean.
        let candidates = [target.selection, target.linkText ?? "", target.linkURL ?? ""]
            .filter { !$0.isEmpty }

        var offered = Set<String>()
        for candidate in candidates {
            for entity in EntityDetector.classify(candidate) {
                let key = "\(entity.kind.rawValue)|\(entity.normalised)"
                guard offered.insert(key).inserted else { continue }
                if let item = menuItem(for: entity, open: open) { items.append(item) }
            }
        }

        if let raw = target.imageURL, let url = URL(string: raw) {
            items.append(imageMenu(for: url, open: open, inspectImage: inspectImage,
                                   transcribeImage: transcribeImage))
        }

        return items
    }

    private static func menuItem(
        for entity: Entity,
        open: @escaping (URL) -> Void
    ) -> NSMenuItem? {
        let groups = PivotRegistry.grouped(for: entity.kind)
        guard !groups.isEmpty else { return nil }

        let submenu = NSMenu()
        for (index, group) in groups.enumerated() {
            if index > 0 { submenu.addItem(.separator()) }
            for source in group.sources {
                guard let url = source.url(for: entity) else { continue }
                let item = NSMenuItem(
                    title: source.requiresAccount ? "\(source.name) (account needed)" : source.name,
                    action: nil, keyEquivalent: ""
                )
                item.representedObject = url
                item.target = ActionProxy.shared
                item.action = #selector(ActionProxy.run(_:))
                ActionProxy.shared.register(url) { open(url) }
                submenu.addItem(item)
            }
        }

        // The value is in the title, truncated: an investigator needs to see *which* address
        // they are about to look up when a page contains several.
        let shown = entity.normalised.count > 48
            ? entity.normalised.prefix(45) + "…"
            : entity.normalised[...]
        let item = NSMenuItem(title: "\(entity.kind.displayName): \(shown)", action: nil, keyEquivalent: "")
        item.submenu = submenu
        return item
    }

    private static func imageMenu(
        for url: URL,
        open: @escaping (URL) -> Void,
        inspectImage: @escaping (URL) -> Void,
        transcribeImage: @escaping (URL) -> Void
    ) -> NSMenuItem {
        let submenu = NSMenu()

        let metadata = NSMenuItem(title: "Inspect metadata…", action: #selector(ActionProxy.run(_:)), keyEquivalent: "")
        metadata.target = ActionProxy.shared
        metadata.representedObject = url
        ActionProxy.shared.register(url) { inspectImage(url) }
        submenu.addItem(metadata)

        // A distinct URL key, since the proxy maps by URL and this is a second action on the
        // same image.
        if var components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            components.fragment = "shinobi-transcribe"
            if let key = components.url {
                let transcribe = NSMenuItem(title: "Transcribe text…", action: #selector(ActionProxy.run(_:)), keyEquivalent: "")
                transcribe.target = ActionProxy.shared
                transcribe.representedObject = key
                ActionProxy.shared.register(key) { transcribeImage(url) }
                submenu.addItem(transcribe)
            }
        }
        submenu.addItem(.separator())

        for engine in ReverseImageSearch.engines {
            guard let searchURL = engine.url(for: url) else { continue }
            let item = NSMenuItem(title: engine.name, action: #selector(ActionProxy.run(_:)), keyEquivalent: "")
            item.target = ActionProxy.shared
            item.representedObject = searchURL
            ActionProxy.shared.register(searchURL) { open(searchURL) }
            submenu.addItem(item)
        }

        let item = NSMenuItem(title: "Image", action: nil, keyEquivalent: "")
        item.submenu = submenu
        return item
    }
}

/// Routes menu selections back to closures.
///
/// `NSMenuItem` needs an Objective-C target and selector, which a closure cannot be. Keeping
/// the mapping here rather than making every call site an `@objc` method keeps the menu
/// construction readable.
@MainActor
final class ActionProxy: NSObject {
    static let shared = ActionProxy()

    private var handlers: [URL: () -> Void] = [:]

    func register(_ url: URL, _ handler: @escaping () -> Void) {
        handlers[url] = handler
    }

    @objc func run(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        handlers[url]?()
    }

    /// Cleared when a menu closes, so the table does not grow for the life of the session.
    func clear() { handlers.removeAll() }
}
