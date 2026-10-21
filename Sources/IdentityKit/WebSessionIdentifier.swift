// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

/// Validates a identity id before it reaches WebKit.
///
/// `WKWebsiteDataStore(forIdentifier:)` rejects some UUIDs by raising an
/// `NSInvalidArgumentException`. That is an Objective-C exception, not a Swift error, so it
/// cannot be caught — it unwinds straight through Swift frames, and when it happens during
/// app startup AppKit swallows it and carries on with a half-constructed window, which is a
/// remarkably difficult failure to read from the outside.
///
/// The rejected values, established by testing the API directly rather than by reading the
/// error message: a UUID whose 128-bit value is **0 or 1**. WebKit reserves those two as
/// empty and deleted sentinels for its own hash tables. Everything else is accepted —
/// including UUIDs with a zero version field, which is what the phrasing of the exception
/// first suggests is the problem.
///
/// So identity ids are checked here, up front, and turned into a Swift error that the
/// caller can actually handle.
public enum WebSessionIdentifier {

    public static func validate(_ id: UUID) throws {
        guard !isReserved(id) else { throw ValidationError.reservedIdentifier(id) }
    }

    /// Whether WebKit reserves this UUID for internal use.
    public static func isReserved(_ id: UUID) -> Bool {
        let bytes = id.uuid
        let allButLastAreZero = bytes.0 == 0 && bytes.1 == 0 && bytes.2 == 0 && bytes.3 == 0
            && bytes.4 == 0 && bytes.5 == 0 && bytes.6 == 0 && bytes.7 == 0
            && bytes.8 == 0 && bytes.9 == 0 && bytes.10 == 0 && bytes.11 == 0
            && bytes.12 == 0 && bytes.13 == 0 && bytes.14 == 0
        return allButLastAreZero && (bytes.15 == 0 || bytes.15 == 1)
    }

    public enum ValidationError: Error, LocalizedError, Equatable {
        case reservedIdentifier(UUID)

        public var errorDescription: String? {
            switch self {
            case .reservedIdentifier(let id):
                "The identity identifier \(id.uuidString) is reserved by WebKit and cannot "
                + "be used for an isolated session."
            }
        }
    }
}
