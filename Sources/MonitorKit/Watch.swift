// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import ShinobiKit

/// A page being watched for change.
public struct Watch: Codable, Identifiable, Sendable, Equatable {

    public enum Interval: String, Codable, Sendable, CaseIterable {
        case fifteenMinutes
        case hourly
        case sixHourly
        case daily

        public var displayName: String {
            switch self {
            case .fifteenMinutes: "Every 15 minutes"
            case .hourly: "Hourly"
            case .sixHourly: "Every 6 hours"
            case .daily: "Daily"
            }
        }

        public var seconds: TimeInterval {
            switch self {
            case .fifteenMinutes: 15 * 60
            case .hourly: 60 * 60
            case .sixHourly: 6 * 60 * 60
            case .daily: 24 * 60 * 60
            }
        }
    }

    public let id: UUID
    public var name: String
    public var url: String
    /// The identity the check is made as, so a watched page is polled from the same address
    /// the investigator browsed it from.
    public var identityID: UUID
    public var interval: Interval
    public var sensitivity: ChangeDetector.Sensitivity
    /// Case to record changes into. Nil watches only notify.
    public var casePath: String?
    public var isEnabled: Bool

    // Observed state
    public var lastCheckedAt: Date?
    public var lastChangedAt: Date?
    /// Digest of the text seen last time, for comparison.
    public var lastDigest: String?
    public var lastLength: Int?
    /// Consecutive failures. A watch that cannot reach its page is not a watch that says
    /// nothing has changed.
    public var consecutiveFailures: Int
    public var lastError: String?

    public init(
        id: UUID = UUID(),
        name: String,
        url: String,
        identityID: UUID,
        interval: Interval = .hourly,
        sensitivity: ChangeDetector.Sensitivity = .moderate,
        casePath: String? = nil,
        isEnabled: Bool = true
    ) {
        self.id = id
        self.name = name
        self.url = url
        self.identityID = identityID
        self.interval = interval
        self.sensitivity = sensitivity
        self.casePath = casePath
        self.isEnabled = isEnabled
        self.consecutiveFailures = 0
    }

    /// Whether this watch is due.
    ///
    /// The interval is jittered by up to a fifth. Polling a subject's page at exactly the
    /// same second past the hour, forever, is a pattern in their access logs that says
    /// somebody is watching — and an unusually legible one. Jitter does not make monitoring
    /// invisible, but it stops the schedule itself being the tell.
    public func isDue(at now: Date = Date(), jitter: TimeInterval = 0) -> Bool {
        guard isEnabled else { return false }
        guard let last = lastCheckedAt else { return true }
        return now.timeIntervalSince(last) >= interval.seconds + jitter
    }

    /// Jitter to apply to the next check, in seconds.
    public static func jitter(for interval: Interval) -> TimeInterval {
        .random(in: 0...(interval.seconds * 0.2))
    }

    public var statusLine: String {
        if !isEnabled { return "Paused" }
        if consecutiveFailures > 0 {
            return "\(consecutiveFailures) failed check(s)" + (lastError.map { " — \($0)" } ?? "")
        }
        if let changed = lastChangedAt {
            return "Last changed \(changed.formatted(date: .abbreviated, time: .shortened))"
        }
        if let checked = lastCheckedAt {
            return "No change since \(checked.formatted(date: .abbreviated, time: .shortened))"
        }
        return "Not yet checked"
    }
}

/// The watch list.
public final class WatchStore: @unchecked Sendable {

    private let fileURL: URL
    private let queue = DispatchQueue(label: "com.shinobi.browser.watch-store")
    private var watches: [Watch]

    public var onChange: (@Sendable ([Watch]) -> Void)?

    public init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? Self.defaultFileURL()
        self.watches = Self.load(from: self.fileURL)
    }

    public static func defaultFileURL() -> URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Shinobi", isDirectory: true)
        try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        return support.appendingPathComponent("watches.json")
    }

    public var all: [Watch] { queue.sync { watches } }

    public func watch(withID id: UUID) -> Watch? {
        queue.sync { watches.first { $0.id == id } }
    }

    public func add(_ watch: Watch) throws { try mutate { $0.append(watch) } }

    public func update(_ watch: Watch) throws {
        try mutate { list in
            guard let index = list.firstIndex(where: { $0.id == watch.id }) else { return }
            list[index] = watch
        }
    }

    public func remove(id: UUID) throws {
        try mutate { $0.removeAll { $0.id == id } }
    }

    /// Watches due for a check now.
    public func due(at now: Date = Date()) -> [Watch] {
        all.filter { $0.isDue(at: now) }
    }

    private func mutate(_ body: (inout [Watch]) -> Void) throws {
        try queue.sync {
            body(&watches)
            let data = try JSONEncoder.shinobi(prettyPrinted: true).encode(watches)
            try data.write(to: fileURL, options: .atomic)
        }
        let snapshot = all
        let handler = onChange
        DispatchQueue.main.async { handler?(snapshot) }
    }

    private static func load(from url: URL) -> [Watch] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder.shinobi().decode([Watch].self, from: data)) ?? []
    }
}
