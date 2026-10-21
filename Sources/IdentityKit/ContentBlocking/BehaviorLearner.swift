// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

/// Learns third-party trackers by behaviour, the way Privacy Badger does: a third-party
/// domain that turns up across enough *distinct* first-party sites is acting like a tracker,
/// whoever it is, and gets blocked — without anyone having to list it.
///
/// WebKit does not let Shinobi watch every request (see ADR-0002), so the observations come
/// from a script that reports each page's third-party domains. This type is the memory and
/// the judgement: which domains have been seen widely enough to earn a block. It is pure and
/// deterministic, so the decision is testable without a browser.
public final class BehaviorLearner: @unchecked Sendable {

    /// How many distinct first-party sites a third party must appear on to be called tracking.
    public let threshold: Int

    private var seenBy: [String: Set<String>] = [:]   // third-party domain → first-party sites
    private let fileURL: URL?
    private let lock = NSLock()

    public init(threshold: Int = 3, fileURL: URL? = nil) {
        self.threshold = max(2, threshold)
        self.fileURL = fileURL ?? Self.defaultFileURL()
        load()
    }

    /// Folds one page's observations in. Returns true when this observation pushed a new
    /// domain over the threshold — the caller recompiles the block list only when that happens.
    @discardableResult
    public func observe(firstParty: String, thirdParties: [String]) -> Bool {
        let first = firstParty.lowercased()
        guard !first.isEmpty else { return false }

        lock.lock(); defer { lock.unlock() }
        var promoted = false
        for raw in thirdParties {
            let third = raw.lowercased()
            guard !third.isEmpty, third != first else { continue }
            let wasTracking = (seenBy[third]?.count ?? 0) >= threshold
            // Only ever need to know whether the set has reached the threshold, so cap growth.
            if (seenBy[third]?.count ?? 0) <= threshold {
                seenBy[third, default: []].insert(first)
            }
            if !wasTracking, (seenBy[third]?.count ?? 0) >= threshold {
                promoted = true
            }
        }
        if promoted { save() }
        return promoted
    }

    /// The domains seen tracking across at least `threshold` distinct sites.
    public func trackers() -> [String] {
        lock.lock(); defer { lock.unlock() }
        return seenBy.filter { $0.value.count >= threshold }.keys.sorted()
    }

    /// Forgets everything learned. For a privacy reset.
    public func reset() {
        lock.lock(); seenBy = [:]; lock.unlock()
        save()
    }

    // MARK: Persistence

    private func load() {
        guard let fileURL, let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([String: [String]].self, from: data) else { return }
        seenBy = decoded.mapValues(Set.init)
    }

    private func save() {
        guard let fileURL else { return }
        let plain = seenBy.mapValues(Array.init)
        guard let data = try? JSONEncoder().encode(plain) else { return }
        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: fileURL, options: .atomic)
    }

    static func defaultFileURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Shinobi", isDirectory: true)
        return base.appendingPathComponent("behavioral-trackers.json")
    }
}
