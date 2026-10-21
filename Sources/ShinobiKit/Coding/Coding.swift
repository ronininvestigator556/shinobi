// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

/// The JSON coders every persisted Shinobi structure uses.
///
/// Centralised so a value written by one part of the app and read by another cannot
/// disagree about format, and so that timestamps survive a save/reload unchanged.
///
/// That second property is harder than it looks, and the shape of this file is the result
/// of measuring rather than assuming. `Date` is a `Double`, and an ISO-8601 string with
/// milliseconds cannot express it: over 20,000 random dates, encoding with fractional
/// seconds and decoding produced a *different* `Date` roughly half the time. Normalising the
/// value through the formatter first does not help — the text is stable, but the `Double`
/// reconstructed from it is not, so `date == decoded` still fails. Whole seconds round-trip
/// exactly, 20,000 times out of 20,000, because integer second counts are exactly
/// representable as `Double`.
///
/// So Shinobi persists timestamps at whole-second precision and normalises them on
/// construction, which makes *the value in memory equal the value on disk* an invariant the
/// tests can assert. When capture times arrive and sub-second resolution genuinely matters,
/// they must carry their canonical text form rather than relying on `Date` equality — the
/// measurement above is why.
public extension JSONEncoder {
    static func shinobi(prettyPrinted: Bool = false) -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = prettyPrinted ? [.prettyPrinted, .sortedKeys] : [.sortedKeys]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var identity = encoder.singleValueContainer()
            try identity.encode(date.formatted(Date.ISO8601FormatStyle.shinobiTimestamp))
        }
        return encoder
    }
}

public extension JSONDecoder {
    static func shinobi() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let text = try decoder.singleValueContainer().decode(String.self)
            guard let date = try? Date(text, strategy: Date.ISO8601FormatStyle.shinobiTimestamp) else {
                throw DecodingError.dataCorrupted(.init(
                    codingPath: decoder.codingPath,
                    debugDescription: "Expected an ISO-8601 timestamp, got '\(text)'"
                ))
            }
            return date
        }
        return decoder
    }
}

public extension Date.ISO8601FormatStyle {
    /// UTC, whole seconds.
    ///
    /// A format *style* rather than an `ISO8601DateFormatter`: the style is a `Sendable`
    /// value type, so it can be shared freely across actors, where a reference-typed
    /// formatter would need locking to satisfy Swift 6's concurrency checking.
    static var shinobiTimestamp: Date.ISO8601FormatStyle {
        Date.ISO8601FormatStyle(includingFractionalSeconds: false, timeZone: .gmt)
    }
}

public extension Date {
    /// The date at the precision Shinobi actually writes to disk.
    ///
    /// Timestamps are normalised here, at the point they are created, so that a value never
    /// changes underneath its owner the first time it is saved. See the note on
    /// `JSONEncoder.shinobi` for the measurements behind the chosen precision.
    func roundedToPersistedPrecision() -> Date {
        Date(timeIntervalSinceReferenceDate: timeIntervalSinceReferenceDate.rounded())
    }
}
