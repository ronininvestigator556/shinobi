// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import ShinobiKit

/// The persisted list of identities.
///
/// Backed by a JSON file rather than `UserDefaults`: the identity list is investigative
/// configuration an examiner may need to inspect or hand over, and a file that can be opened
/// in a text editor is worth more than a binary plist. It is also small, read once at launch,
/// and written rarely, so there is no reason to reach for a database.
public final class IdentityStore: @unchecked Sendable {

    private let fileURL: URL
    private let queue = DispatchQueue(label: "com.shinobi.browser.identity-store")
    private var identities: [Identity]

    /// Raised after any mutation, so the UI can reload. Always delivered on the main queue.
    public var onChange: (@Sendable ([Identity]) -> Void)?

    public init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? Self.defaultFileURL()
        self.identities = Self.load(from: self.fileURL)

        // The personal identity is not optional and not deletable. Guaranteeing it exists
        // here means the rest of the app never has to handle "no identities at all", which
        // would otherwise be a state where a tab has nowhere to live.
        if !identities.contains(where: { $0.isPersonal }) {
            identities.insert(.personal, at: 0)
            try? persist()
        }
    }

    public static func defaultFileURL() -> URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Shinobi", isDirectory: true)
        try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        return support.appendingPathComponent("identities.json")
    }

    // MARK: Reading

    public var all: [Identity] {
        queue.sync { identities }
    }

    public func identity(withID id: UUID) -> Identity? {
        queue.sync { identities.first { $0.id == id } }
    }

    // MARK: Writing

    public func add(_ identity: Identity) throws {
        try mutate { $0.append(identity) }
    }

    public func update(_ identity: Identity) throws {
        try mutate { list in
            guard let index = list.firstIndex(where: { $0.id == identity.id }) else { return }
            list[index] = identity
        }
    }

    /// Removes a identity and everything belonging to it.
    ///
    /// Deleting a identity is a destructive act with a real consequence — the persona's
    /// sessions, cookies and local storage go with it — so the caller is responsible for
    /// confirming with the user first. The web site data store itself is torn down by
    /// `IdentitySessionProvider`, which owns it; this only forgets the configuration and
    /// the credential.
    public func remove(id: UUID) throws {
        guard id != Identity.personal.id else { throw StoreError.cannotRemovePersonal }
        try mutate { $0.removeAll { $0.id == id } }
        try? ProxyCredentialStore.delete(forContainer: id)
    }

    private func mutate(_ body: (inout [Identity]) -> Void) throws {
        try queue.sync {
            body(&identities)
            try persist()
        }
        let snapshot = all
        let handler = onChange
        DispatchQueue.main.async { handler?(snapshot) }
    }

    // MARK: Persistence

    private func persist() throws {
        let data = try JSONEncoder.shinobi(prettyPrinted: true).encode(identities)
        // Atomic, so an interrupted write cannot leave a truncated file that would lose
        // every identity on next launch.
        try data.write(to: fileURL, options: .atomic)
    }

    private static func load(from url: URL) -> [Identity] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder.shinobi().decode([Identity].self, from: data)) ?? []
    }

    public enum StoreError: Error, LocalizedError {
        case cannotRemovePersonal

        public var errorDescription: String? {
            switch self {
            case .cannotRemovePersonal:
                "The Personal identity cannot be deleted."
            }
        }
    }
}
