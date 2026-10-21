// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import WebKit

/// Serialises a live page into a self-contained HTML archive.
@MainActor
public enum PageArchiver {

    /// Largest single resource that will be inlined.
    public static let maximumResourceBytes = 8 * 1024 * 1024
    /// Ceiling on everything inlined into one archive.
    public static let maximumTotalBytes = 48 * 1024 * 1024

    public struct Archive: Sendable, Equatable {
        public let html: String
        public let stats: Stats
        /// Human-readable caveats belonging with this artifact, and with any exhibit made
        /// from it.
        public let notes: [String]

        public var data: Data { Data(html.utf8) }
    }

    /// What the serialiser managed and what it did not.
    ///
    /// Reported rather than kept internal: an exhibit's fidelity is a fact about the exhibit,
    /// and an investigator asked "is this everything?" needs a specific answer.
    public struct Stats: Sendable, Equatable {
        public var stylesheetsInlined = 0
        public var stylesheetsFailed = 0
        public var imagesInlined = 0
        public var imagesFailed = 0
        public var fontsInlined = 0
        public var canvasesRasterised = 0
        public var framesInlined = 0
        public var framesSkipped = 0
        public var scriptsRemoved = 0
        public var handlersRemoved = 0
        public var remoteReferencesNeutralised = 0
        public var noscriptBlocksRemoved = 0
        public var bytesInlined = 0

        /// Whether anything was lost. Drives whether the capture is flagged in the interface.
        public var isComplete: Bool {
            stylesheetsFailed == 0 && imagesFailed == 0 && framesSkipped == 0
        }

        init(from raw: [String: Any]) {
            func value(_ key: String) -> Int { (raw[key] as? NSNumber)?.intValue ?? 0 }
            stylesheetsInlined = value("stylesheetsInlined")
            stylesheetsFailed = value("stylesheetsFailed")
            imagesInlined = value("imagesInlined")
            imagesFailed = value("imagesFailed")
            fontsInlined = value("fontsInlined")
            canvasesRasterised = value("canvasesRasterised")
            framesInlined = value("framesInlined")
            framesSkipped = value("framesSkipped")
            scriptsRemoved = value("scriptsRemoved")
            handlersRemoved = value("handlersRemoved")
            remoteReferencesNeutralised = value("remoteReferencesNeutralised")
            noscriptBlocksRemoved = value("noscriptBlocksRemoved")
            bytesInlined = value("bytesInlined")
        }

        public init() {}
    }

    public enum ArchiveError: Error, LocalizedError {
        case scriptFailed(String)
        case unexpectedResult

        public var errorDescription: String? {
            switch self {
            case .scriptFailed(let detail): "The page could not be archived: \(detail)"
            case .unexpectedResult: "The page archiver returned something unexpected."
            }
        }
    }

    public static func archive(_ webView: WKWebView) async throws -> Archive {
        let result: Any?
        do {
            result = try await webView.callAsyncJavaScript(
                PageArchiverScript.source,
                arguments: [
                    "maxResourceBytes": maximumResourceBytes,
                    "maxTotalBytes": maximumTotalBytes,
                ],
                contentWorld: .defaultClient
            )
        } catch {
            throw ArchiveError.scriptFailed(error.localizedDescription)
        }

        guard
            let payload = result as? [String: Any],
            let html = payload["html"] as? String,
            let rawStats = payload["stats"] as? [String: Any]
        else { throw ArchiveError.unexpectedResult }

        return Archive(
            html: html,
            stats: Stats(from: rawStats),
            notes: (payload["notes"] as? [String]) ?? []
        )
    }
}
