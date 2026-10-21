// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import GRDB
import ShinobiKit

/// Produces a self-contained folder a case can be handed over in.
///
/// The design constraint is that the recipient may have no interest in Shinobi and no reason to
/// trust it. So the export contains no Shinobi-specific format: artifacts are ordinary files
/// with ordinary extensions, the inventory is JSON, the signature is checkable with `openssl`,
/// and the checksums file is the exact format `shasum -c` expects. Someone can verify the
/// whole thing with tools already on their machine.
public struct CaseExport {

    public struct Summary: Sendable, Equatable {
        public let destination: URL
        public let artifactCount: Int
        public let visitCount: Int
        public let byteCount: Int
    }

    private let store: CaseStore
    private let exhibitsOnly: Bool

    /// - Parameter exhibitsOnly: when true, pages that were only logged — text and nothing
    ///   else — are left out, so the bundle carries the exhibits that were deliberately
    ///   captured rather than everything that was passed through. The manifest still says how
    ///   many pages were omitted, because a recipient is entitled to know the export is a
    ///   selection rather than the whole record.
    public init(store: CaseStore, exhibitsOnly: Bool = false) {
        self.store = store
        self.exhibitsOnly = exhibitsOnly
    }

    /// Writes the export. Refuses to overwrite: an export is a snapshot handed to someone,
    /// and silently replacing one that may already have been sent is not recoverable.
    @discardableResult
    public func write(to destination: URL) throws -> Summary {
        guard !FileManager.default.fileExists(atPath: destination.path) else {
            throw CaseError.bundleAlreadyExists(destination)
        }

        let files = destination.appendingPathComponent("artifacts", isDirectory: true)
        try FileManager.default.createDirectory(at: files, withIntermediateDirectories: true)

        // Reuse the manifest already on disk when it still describes the case exactly.
        //
        // Rewriting it unconditionally was a real defect: `generatedAt` changes on every
        // write, so an export silently produced a manifest whose bytes no longer matched the
        // RFC 3161 token taken over the previous one. A recipient running
        // `openssl ts -verify -data manifest.json` would have been told the timestamp did not
        // cover the file — valid evidence made to look invalid, which is the worst way to be
        // wrong here.
        let full = try store.manifestMatchingDiskOrRewritten()
        let blobs = store.bundle.blobStore

        // Pages carrying nothing but text were logged rather than captured.
        let visitsWithExhibits = Set(full.entries.filter { $0.kind != "text" }.map(\.visitID))
        let manifest = exhibitsOnly
            ? full.selecting(visitIDs: visitsWithExhibits)
            : full
        let omittedVisits = exhibitsOnly
            ? Set(full.entries.map(\.visitID)).subtracting(visitsWithExhibits).count
            : 0

        var checksums: [String] = []
        var totalBytes = 0
        var warc = WARCWriter(caseName: manifest.caseName)

        for (index, entry) in manifest.entries.enumerated() {
            let data = try blobs.data(for: entry.digest)
            let name = Self.fileName(index: index + 1, entry: entry)
            try data.write(to: files.appendingPathComponent(name), options: .atomic)

            // Exactly the format `shasum -a 256 -c` reads.
            checksums.append("\(entry.digest)  artifacts/\(name)")
            totalBytes += data.count

            if let kind = Artifact.Kind(rawValue: entry.kind) {
                warc.addResource(
                    uri: entry.url,
                    contentType: WARCWriter.contentType(for: kind),
                    capturedAt: (try? Date(entry.visitedAt, strategy: Date.ISO8601FormatStyle.shinobiTimestamp)) ?? Date(),
                    payload: data,
                    note: entry.note
                )
            }
        }

        // A filtered export gets its own manifest and its own signature over that manifest.
        // Shipping the full manifest beside a subset of the artifacts would fail
        // verification and look like tampering.
        let manifestData: Data
        let signatureData: Data
        if exhibitsOnly {
            manifestData = try manifest.canonicalData()
            signatureData = try store.sign(manifestData).base64EncodedData()
        } else {
            manifestData = try Data(contentsOf: store.bundle.manifestURL)
            signatureData = try Data(contentsOf: store.bundle.url.appendingPathComponent("manifest.sig"))
        }
        try manifestData.write(to: destination.appendingPathComponent("manifest.json"), options: .atomic)
        try signatureData.write(to: destination.appendingPathComponent("manifest.sig"), options: .atomic)
        try Self.publicKeyPEM(base64Raw: manifest.publicKey)
            .write(to: destination.appendingPathComponent("public-key.pem"), atomically: true, encoding: .utf8)

        // The token covers the case's own manifest, so it travels only with an unfiltered
        // export whose manifest is byte-identical to the one that was timestamped. A filtered
        // export re-signs different bytes, and shipping a token over bytes that are not in
        // the folder would be worse than shipping none.
        var timestamped = false
        if !exhibitsOnly,
           let token = try? Data(contentsOf: store.bundle.timestampURL),
           let onDisk = try? Data(contentsOf: store.bundle.manifestURL),
           onDisk == (try? full.canonicalData()) {
            try token.write(to: destination.appendingPathComponent("manifest.tsr"), options: .atomic)
            timestamped = true
        }

        let warcURL = destination.appendingPathComponent("\(manifest.caseName).warc")
        try warc.data().write(to: warcURL, options: .atomic)

        checksums.append("\(BlobStore.digest(of: manifestData))  manifest.json")
        try (checksums.joined(separator: "\n") + "\n")
            .write(to: destination.appendingPathComponent("SHA256SUMS"), atomically: true, encoding: .utf8)

        try Self.readme(manifest: manifest, warcName: warcURL.lastPathComponent,
                        omittedVisits: omittedVisits)
            .write(to: destination.appendingPathComponent("README.txt"), atomically: true, encoding: .utf8)

        let visits = Set(manifest.entries.map(\.visitID)).count
        return Summary(
            destination: destination,
            artifactCount: manifest.entries.count,
            visitCount: visits,
            byteCount: totalBytes
        )
    }

    /// Readable, ordered, and traceable back to the manifest by digest.
    static func fileName(index: Int, entry: CaseManifest.Entry) -> String {
        let host = URL(string: entry.url)?.host ?? "page"
        let kind = Artifact.Kind(rawValue: entry.kind)
        let ext = kind?.fileExtension ?? "bin"
        let safeHost = host.replacingOccurrences(of: "/", with: "_")
        return String(format: "%04d-%@-%@-%@.%@",
                      index, safeHost, entry.kind, String(entry.digest.prefix(8)), ext)
    }

    /// Wraps the raw Ed25519 key in a SubjectPublicKeyInfo so `openssl` will read it.
    static func publicKeyPEM(base64Raw: String) -> String {
        guard let raw = Data(base64Encoded: base64Raw), raw.count == 32 else { return "" }
        // DER prefix for an Ed25519 SubjectPublicKeyInfo.
        let prefix = Data([0x30, 0x2a, 0x30, 0x05, 0x06, 0x03, 0x2b, 0x65, 0x70, 0x03, 0x21, 0x00])
        let body = (prefix + raw).base64EncodedString(options: [.lineLength64Characters, .endLineWithLineFeed])
        return "-----BEGIN PUBLIC KEY-----\n\(body)\n-----END PUBLIC KEY-----\n"
    }

    /// Instructions for the timestamp token, when one is present.
    ///
    /// Two checks, because they establish different things and need different prerequisites.
    /// Reading the token works anywhere and shows the time and the hash it covers; full
    /// verification additionally proves the authority signed it, and needs that authority's
    /// root certificate — which this export deliberately does not supply, because a bundle
    /// vouching for its own trust anchor proves nothing.
    static let timestampSection = """

          3. When this inventory existed, attested by an independent authority:

               openssl ts -reply -in manifest.tsr -text

             Read off the "Time stamp" and the "Message data" hash, then confirm that
             hash is the manifest's own:

               shasum -a 256 manifest.json

             The two must match. That establishes these exact bytes existed at that time.

             To also verify the authority's signature you need its root certificate,
             which is not included here — obtain it from the authority named in the token:

               openssl ts -verify -data manifest.json -in manifest.tsr -CAfile <their-root.pem>

        """

    static func readme(
        manifest: CaseManifest,
        warcName: String,
        omittedVisits: Int = 0,
        timestamped: Bool = false
    ) -> String {
        let scope = omittedVisits == 0
            ? "This export contains every page recorded in the case."
            : """
              This export is a selection. \(omittedVisits) page(s) were visited and logged \
              during this investigation but are not included here, because no exhibits were \
              captured for them. The full record remains in the case file.
              """

        return """
        \(manifest.caseName)
        \(String(repeating: "=", count: manifest.caseName.count))

        Reference:  \(manifest.caseReference ?? "none")
        Exported:   \(manifest.generatedAt)
        Artifacts:  \(manifest.entries.count)
        Produced by Shinobi.

        SCOPE

        \(scope)

        CONTENTS

          artifacts/      One file per captured artifact. Names are
                          <number>-<host>-<kind>-<digest prefix>.<extension>.
          manifest.json   Inventory: every artifact with its address, capture time,
                          the identity it was viewed as, its SHA-256 and its size.
          manifest.sig    Ed25519 signature over manifest.json, base64.
          public-key.pem  The matching public key.
          SHA256SUMS      Checksums in the format shasum reads.\(timestamped
          ? "\n          manifest.tsr    RFC 3161 timestamp token over manifest.json."
          : "")
          \(warcName.padding(toLength: max(15, warcName.count), withPad: " ", startingAt: 0))\
        Same artifacts as a WARC 1.1 file, for archival tools.

        VERIFYING THIS EXPORT

        No part of this requires Shinobi.

          1. Every artifact matches its recorded checksum:

               shasum -a 256 -c SHA256SUMS

          2. The inventory has not been altered since it was signed:

               base64 -d < manifest.sig > manifest.sig.bin
               openssl pkeyutl -verify -pubin -inkey public-key.pem \\
                 -rawin -in manifest.json -sigfile manifest.sig.bin

             Both commands are written to work on macOS and Linux as they stand.
             Note the redirect: macOS's base64 will not take a file name as a bare
             argument. If you prefer to use openssl for the decode, it needs -A
             because the signature is a single unwrapped line:

               openssl base64 -d -A -in manifest.sig -out manifest.sig.bin

        \(timestamped ? Self.timestampSection : "")
        WHAT THE SIGNATURE ESTABLISHES

        That this inventory was produced by the installation of Shinobi that made the
        capture, and that it has not been altered since. It does not establish that the
        content is authentic to the website it came from.

        \(timestamped
          ? "Timing is attested separately by the token described above, issued by an authority independent of this investigation."
          : "It also does not establish when the capture happened to anyone who does not already accept the operator's clock. That needs a third party, such as a trusted timestamp authority; no such timestamp accompanies this export.")

        HOW THE PAGES WERE CAPTURED

        Artifacts were produced from pages as rendered in the browser, not captured from
        the network. HTML archives therefore have no original HTTP headers, and the WARC
        records are of type "resource" rather than "response" for that reason.

        HTML archives are inert: scripts, event handlers and anything that would load
        from the network when the file is opened have been removed. Original URLs are
        preserved in data-shinobi-blocked-* attributes. Ordinary links are left intact and
        will work if followed.

        Where a page could not be captured completely — a stylesheet that could not be
        read, an image that could not be retrieved, a cross-origin frame — the manifest
        entry for that artifact says so in its note.
        """
    }
}
