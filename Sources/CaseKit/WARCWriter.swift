// SPDX-License-Identifier: GPL-3.0-or-later
import CryptoKit
import Foundation
import ShinobiKit

/// Writes WARC 1.1 files.
///
/// WARC is the archival standard, which matters because it is what a preservation specialist
/// or an opposing expert will already have tools for — pywb, replayweb.page, warcio — and a
/// case that can only be opened by the program that made it is worth less than one that
/// cannot.
///
/// **Every record is a `resource`, never a `response`.** A `response` record asserts that it
/// contains the complete HTTP response, headers included, exactly as the server sent it.
/// Shinobi cannot honestly write one: `WKWebView` gives no way to intercept requests, so the
/// archive is reconstructed from the rendered page rather than captured off the wire. The
/// spec's `resource` type means precisely "a resource captured by some other means", which is
/// what these are. Writing plausible-looking `response` records with invented headers would
/// make the files look more authoritative and be a lie about their provenance.
///
/// Written uncompressed rather than gzipped. A `.warc.gz` is normally gzipped per record so
/// that an index can seek into it; gzipping the whole file instead produces something that
/// looks conventional but breaks random access. Uncompressed is unambiguously valid, readable
/// with `less`, and the case bundle is not where space is scarce.
public struct WARCWriter {

    public static let version = "WARC/1.1"
    private static let crlf = Data("\r\n".utf8)

    private var records = Data()
    private let warcinfoID: String

    public init(caseName: String, generatedAt: Date = Date()) {
        self.warcinfoID = Self.recordID()

        let fields = """
        software: Shinobi
        format: WARC File Format 1.1
        conformsTo: http://iipc.github.io/warc-specifications/specifications/warc-format/warc-1.1/
        description: Artifacts captured from rendered pages. Records are of type 'resource', \
        not 'response': the content was reconstructed from the loaded page rather than \
        captured from the network, so no original HTTP headers are available and none are \
        invented.
        case: \(caseName)

        """.replacingOccurrences(of: "\n", with: "\r\n")

        appendRecord(
            headers: [
                ("WARC-Type", "warcinfo"),
                ("WARC-Date", Self.timestamp(generatedAt)),
                ("WARC-Record-ID", warcinfoID),
                ("WARC-Filename", "\(caseName).warc"),
                ("Content-Type", "application/warc-fields"),
            ],
            block: Data(fields.utf8)
        )
    }

    /// Adds one captured artifact.
    @discardableResult
    public mutating func addResource(
        uri: String,
        contentType: String,
        capturedAt: Date,
        payload: Data,
        note: String? = nil
    ) -> String {
        let id = Self.recordID()
        appendRecord(
            headers: [
                ("WARC-Type", "resource"),
                ("WARC-Date", Self.timestamp(capturedAt)),
                ("WARC-Record-ID", id),
                ("WARC-Target-URI", uri),
                ("WARC-Warcinfo-ID", warcinfoID),
                ("WARC-Block-Digest", "sha256:" + Self.hexDigest(payload)),
                ("Content-Type", contentType),
            ],
            block: payload
        )

        if let note {
            // Fidelity caveats travel with the record rather than living only in Shinobi's
            // database, so they survive the file being handed to someone else.
            let fields = "note: \(note)\r\n".replacingOccurrences(of: "\n", with: "\r\n")
            appendRecord(
                headers: [
                    ("WARC-Type", "metadata"),
                    ("WARC-Date", Self.timestamp(capturedAt)),
                    ("WARC-Record-ID", Self.recordID()),
                    ("WARC-Target-URI", uri),
                    ("WARC-Refers-To", id),
                    ("WARC-Warcinfo-ID", warcinfoID),
                    ("Content-Type", "application/warc-fields"),
                ],
                block: Data(fields.utf8)
            )
        }

        return id
    }

    public func data() -> Data { records }

    // MARK: Record assembly

    private mutating func appendRecord(headers: [(String, String)], block: Data) {
        var head = Self.version + "\r\n"
        for (name, value) in headers {
            head += "\(name): \(value)\r\n"
        }
        // Content-Length is written last and always computed, never taken on trust.
        head += "Content-Length: \(block.count)\r\n"

        records.append(Data(head.utf8))
        records.append(Self.crlf)      // blank line ends the header block
        records.append(block)
        // The spec requires exactly two CRLF after the block.
        records.append(Self.crlf)
        records.append(Self.crlf)
    }

    private static func recordID() -> String { "<urn:uuid:\(UUID().uuidString.lowercased())>" }

    private static func timestamp(_ date: Date) -> String {
        date.roundedToPersistedPrecision().formatted(Date.ISO8601FormatStyle.shinobiTimestamp)
    }

    private static func hexDigest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// The WARC media type for an artifact kind.
    public static func contentType(for kind: Artifact.Kind) -> String {
        switch kind {
        case .text: "text/plain; charset=utf-8"
        case .archive: "text/html; charset=utf-8"
        case .screenshot: "image/png"
        case .pdf: "application/pdf"
        case .ocr: "text/plain; charset=utf-8"
        }
    }
}
