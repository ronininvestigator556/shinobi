// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

/// Summarises a page using the on-device model.
///
/// **What this is for, and what it is not.** Summarising is a reading aid: it helps an
/// investigator decide whether a long page is worth their attention. It is not evidence, it is
/// never stored as an artifact, and it never reaches an export. Everything a summary says is
/// already in the page text, which *is* stored and hashed — so the summary can always be
/// checked against the record it describes.
///
/// **Entities are deliberately not extracted this way.** A language model asked to list the
/// people on a page will, sometimes, list a person who is not on it — and a fabricated name in
/// an investigation is worse than no name, because it is actionable. `NamedEntities` uses a
/// deterministic tagger for that job: it reports what it found and cannot invent.
///
/// On device, so the subject's page never leaves the machine to be read.
public struct PageSummariser: Sendable {

    public enum Availability: Sendable, Equatable {
        case available
        case unavailable(String)

        public var isAvailable: Bool { self == .available }
    }

    public struct Summary: Sendable, Equatable {
        public let text: String
        /// True when the page was longer than the model was given.
        public let truncated: Bool

        /// The label this must be shown under. Not optional, and not paraphrasable.
        public var disclaimer: String {
            "Written by an on-device language model as a reading aid. Not evidence, not stored "
            + "in the case, and not included in exports. Check it against the recorded page "
            + "text before relying on anything in it."
            + (truncated ? " Only the first part of the page was read." : "")
        }
    }

    /// Characters handed to the model.
    ///
    /// Bounded because the context window is, and truncation is reported rather than hidden:
    /// a summary of the first quarter of a document that reads as a summary of the whole is
    /// actively misleading.
    public static let inputLimit = 6000

    public init() {}

    public func availability() -> Availability {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            switch SystemLanguageModel.default.availability {
            case .available:
                return .available
            case .unavailable(let reason):
                return .unavailable(Self.describe(reason))
            }
        }
        return .unavailable("This version of macOS has no on-device model.")
        #else
        return .unavailable("This build has no on-device model.")
        #endif
    }

    public func summarise(_ text: String) async throws -> Summary {
        #if canImport(FoundationModels)
        guard #available(macOS 26.0, *) else { throw SummaryError.unavailable }
        guard case .available = availability() else { throw SummaryError.unavailable }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 200 else { throw SummaryError.tooShort }

        let truncated = trimmed.count > Self.inputLimit
        let input = truncated ? String(trimmed.prefix(Self.inputLimit)) : trimmed

        let session = LanguageModelSession(instructions: """
            You summarise web pages for an investigator who needs to decide quickly whether a \
            page is worth reading in full.

            Write three sentences at most. State only what the page says. Do not speculate, \
            do not infer motives, and do not add background you were not given. If the page \
            names people, organisations or places, mention the ones it is actually about. If \
            the text is too fragmentary to summarise, say so plainly instead of guessing.
            """)

        let response = try await session.respond(to: "Summarise this page:\n\n\(input)")
        return Summary(
            text: response.content.trimmingCharacters(in: .whitespacesAndNewlines),
            truncated: truncated
        )
        #else
        throw SummaryError.unavailable
        #endif
    }

    #if canImport(FoundationModels)
    @available(macOS 26.0, *)
    private static func describe(_ reason: SystemLanguageModel.Availability.UnavailableReason) -> String {
        switch reason {
        case .deviceNotEligible:
            "This Mac does not support the on-device model."
        case .appleIntelligenceNotEnabled:
            "Apple Intelligence is turned off in System Settings."
        case .modelNotReady:
            "The on-device model is still downloading or preparing."
        @unknown default:
            "The on-device model is unavailable."
        }
    }
    #endif

    public enum SummaryError: Error, LocalizedError, Equatable {
        case unavailable
        case tooShort

        public var errorDescription: String? {
            switch self {
            case .unavailable: "The on-device model is not available."
            case .tooShort: "There is not enough text on this page to summarise."
            }
        }
    }
}
