// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import GRDB

/// A `.shinobicase` bundle: everything collected for one investigation.
///
/// A directory rather than a single file. The index is an ordinary SQLite database that any
/// tool can open, the artifacts are ordinary files named by their own digests, and the whole
/// thing can be copied, archived or handed over with `cp -R`. That transparency is the point:
/// an examiner should be able to satisfy themselves about the contents without running
/// Shinobi, and an opposing expert should be able to check the hashes with `shasum`.
///
/// ```
/// Durham-2026-09.shinobicase/
/// ├── case.sqlite     index: visits, notes, custody log, search
/// ├── blobs/          artifacts, named by SHA-256 of their contents
/// └── captures/       replayable page captures (from the capture pipeline)
/// ```
public struct CaseBundle: Sendable {

    public static let fileExtension = "shinobicase"

    public let url: URL

    public var databaseURL: URL { url.appendingPathComponent("case.sqlite") }
    public var blobsURL: URL { url.appendingPathComponent("blobs", isDirectory: true) }
    public var capturesURL: URL { url.appendingPathComponent("captures", isDirectory: true) }
    public var manifestURL: URL { url.appendingPathComponent("manifest.json") }
    public var signatureURL: URL { url.appendingPathComponent("manifest.sig") }
    /// RFC 3161 timestamp token over the manifest, when one has been obtained.
    public var timestampURL: URL { url.appendingPathComponent("manifest.tsr") }

    public var blobStore: BlobStore { BlobStore(root: blobsURL) }

    /// The name shown in the interface, taken from the bundle's file name.
    public var displayName: String { url.deletingPathExtension().lastPathComponent }

    public init(url: URL) {
        self.url = url
    }

    /// Creates the directory structure. Fails if something is already there, rather than
    /// merging into it — silently adopting an existing directory would be a good way to mix
    /// two investigations together.
    public static func create(at url: URL) throws -> CaseBundle {
        guard !FileManager.default.fileExists(atPath: url.path) else {
            throw CaseError.bundleAlreadyExists(url)
        }
        let bundle = CaseBundle(url: url)
        try FileManager.default.createDirectory(at: bundle.url, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: bundle.blobsURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: bundle.capturesURL, withIntermediateDirectories: true)
        return bundle
    }

    public static func open(at url: URL) throws -> CaseBundle {
        let bundle = CaseBundle(url: url)
        guard FileManager.default.fileExists(atPath: bundle.databaseURL.path) else {
            throw CaseError.notACaseBundle(url)
        }
        return bundle
    }
}

public enum CaseError: Error, LocalizedError, Equatable {
    case bundleAlreadyExists(URL)
    case notACaseBundle(URL)
    case noCaseOpen

    public var errorDescription: String? {
        switch self {
        case .bundleAlreadyExists(let url):
            "There is already something at \(url.lastPathComponent)."
        case .notACaseBundle(let url):
            "\(url.lastPathComponent) is not a Shinobi case."
        case .noCaseOpen:
            "No case is open."
        }
    }
}
