// SPDX-License-Identifier: GPL-3.0-or-later
import CryptoKit
import Foundation

/// Obtains an RFC 3161 timestamp over a manifest.
///
/// This is what closes the gap the signed manifest cannot close on its own. A self-signed
/// manifest establishes *what* a case contains and that the list has not been altered; it says
/// nothing about *when*, to anyone who does not already accept the investigator's clock. A
/// timestamp token from an independent authority does: it asserts that these exact bytes
/// existed at a stated time, signed by someone with no stake in the investigation.
///
/// The request contains only a SHA-256 hash. The authority never sees the manifest, the case,
/// or anything about the subject — worth being certain of, because the alternative would be
/// sending the shape of an investigation to a third party in order to prove its timing.
public struct TimestampClient: Sendable {

    /// Authorities that answer unauthenticated requests.
    ///
    /// The default is over **HTTPS**, which matters for a practical reason as well as a
    /// principled one: RFC 3161 authorities are conventionally plain HTTP — the protocol
    /// carries its own signature, so the transport adds nothing to the token's integrity —
    /// but App Transport Security blocks cleartext requests, so an HTTP authority simply
    /// fails on macOS unless the app carries a per-domain exception. Rather than weaken ATS
    /// for every request the app makes, Shinobi prefers authorities that speak TLS.
    ///
    /// Chosen for availability rather than endorsement. Anyone with a preferred authority, or
    /// an evidential reason to use a particular one, should override it.
    public static let defaultAuthority = URL(string: "https://timestamp.sectigo.com")!

    /// Known authorities that answered over TLS when this was written. Offered as a starting
    /// point, not a recommendation.
    public static let knownAuthorities: [(name: String, url: URL)] = [
        ("Sectigo", URL(string: "https://timestamp.sectigo.com")!),
        ("FreeTSA", URL(string: "https://freetsa.org/tsr")!),
    ]

    public let authority: URL
    private let timeout: TimeInterval

    public init(authority: URL = TimestampClient.defaultAuthority, timeout: TimeInterval = 20) {
        self.authority = authority
        self.timeout = timeout
    }

    /// Builds an RFC 3161 `TimeStampReq` over the SHA-256 of `data`.
    ///
    ///     TimeStampReq ::= SEQUENCE {
    ///         version         INTEGER { v1(1) },
    ///         messageImprint  MessageImprint,
    ///         nonce           INTEGER OPTIONAL,
    ///         certReq         BOOLEAN DEFAULT FALSE }
    ///
    /// `certReq` is true so the authority returns its certificate chain inside the token;
    /// without it a recipient would have to source the chain themselves before they could
    /// verify anything.
    public static func request(for data: Data, nonce: Data = Self.freshNonce()) -> Data {
        let digest = Data(SHA256.hash(data: data))

        let algorithm = DER.sequence([
            DER.objectIdentifier(DER.sha256OID),
            DER.null(),
        ])
        let messageImprint = DER.sequence([algorithm, DER.octetString(digest)])

        return DER.sequence([
            DER.integer(1),
            messageImprint,
            DER.integer(bytes: nonce),
            DER.boolean(true),
        ])
    }

    /// A nonce the authority is required to echo back inside the token.
    ///
    /// Shinobi does not itself check that it came back — doing so means walking into the CMS
    /// structure to reach `TSTInfo`, and a half-done job there would be worse than none. It
    /// is sent because a recipient running `openssl ts -verify` *does* check it, and because
    /// its absence would let a recorded reply be presented as a fresh one. Shinobi's own
    /// assurance rests on the TLS connection to the authority and on the authority's
    /// signature over the token.
    public static func freshNonce() -> Data {
        var bytes = [UInt8](repeating: 0, count: 8)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        bytes[0] &= 0x7F      // keep it positive
        return Data(bytes)
    }

    /// Requests a timestamp. Returns the whole `TimeStampResp`, which is what `openssl ts`
    /// reads.
    public func timestamp(_ data: Data) async throws -> Data {
        var request = URLRequest(url: authority)
        request.httpMethod = "POST"
        request.setValue("application/timestamp-query", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = timeout
        request.httpBody = Self.request(for: data)

        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = timeout
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }

        let (body, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw TimestampError.authorityRefused(
                (response as? HTTPURLResponse)?.statusCode ?? -1)
        }

        try Self.checkGranted(body)
        return body
    }

    /// Confirms the authority actually granted the request.
    ///
    /// Checked rather than assumed: a `TimeStampResp` carrying a rejection is still a
    /// well-formed HTTP 200 response, and storing one as though it were a timestamp would put
    /// a file named `manifest.tsr` in an export that proves nothing at all.
    ///
    ///     TimeStampResp ::= SEQUENCE { status PKIStatusInfo, timeStampToken ... }
    ///     PKIStatusInfo  ::= SEQUENCE { status INTEGER, ... }
    static func checkGranted(_ response: Data) throws {
        guard let outer = DER.element(in: response, at: 0), outer.tag == 0x30,
              let statusInfo = DER.element(in: outer.body, at: 0), statusInfo.tag == 0x30,
              let status = DER.element(in: statusInfo.body, at: 0), status.tag == 0x02,
              let value = status.body.first
        else { throw TimestampError.malformedResponse }

        // 0 granted, 1 granted with modifications; anything else is a refusal.
        guard value == 0 || value == 1 else { throw TimestampError.notGranted(Int(value)) }

        // A response with a status but no token would satisfy the check above and still be
        // useless, so require the token too.
        guard statusInfo.end < outer.body.count else { throw TimestampError.noToken }
    }

    public enum TimestampError: Error, LocalizedError, Equatable {
        case authorityRefused(Int)
        case malformedResponse
        case notGranted(Int)
        case noToken

        public var errorDescription: String? {
            switch self {
            case .authorityRefused(let code):
                "The timestamp authority answered with HTTP \(code)."
            case .malformedResponse:
                "The timestamp authority's reply could not be read."
            case .notGranted(let status):
                "The timestamp authority declined the request (status \(status))."
            case .noToken:
                "The timestamp authority replied without a token."
            }
        }
    }
}
