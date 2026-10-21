// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

/// Just enough ASN.1 DER to speak RFC 3161.
///
/// Hand-rolled rather than pulled in as a dependency. The encoder needs four types and the
/// parser needs to read two fields, which is far less code than an ASN.1 library's surface —
/// and a signing-adjacent path is somewhere the amount of code that can go wrong matters more
/// than the convenience of not writing it.
enum DER {

    // MARK: Encoding

    static func integer(_ value: Int) -> Data {
        var magnitude = withUnsafeBytes(of: value.bigEndian, Array.init)
        while magnitude.count > 1, magnitude[0] == 0, magnitude[1] & 0x80 == 0 {
            magnitude.removeFirst()
        }
        // A leading zero keeps a high bit from being read as a negative number.
        if magnitude[0] & 0x80 != 0 { magnitude.insert(0, at: 0) }
        return tagged(0x02, Data(magnitude))
    }

    static func integer(bytes: Data) -> Data {
        var magnitude = [UInt8](bytes)
        while magnitude.count > 1, magnitude[0] == 0, magnitude[1] & 0x80 == 0 {
            magnitude.removeFirst()
        }
        if magnitude.first.map({ $0 & 0x80 != 0 }) == true { magnitude.insert(0, at: 0) }
        return tagged(0x02, Data(magnitude))
    }

    static func octetString(_ data: Data) -> Data { tagged(0x04, data) }
    static func null() -> Data { Data([0x05, 0x00]) }
    static func boolean(_ value: Bool) -> Data { Data([0x01, 0x01, value ? 0xFF : 0x00]) }
    static func objectIdentifier(_ encoded: [UInt8]) -> Data { tagged(0x06, Data(encoded)) }
    static func sequence(_ parts: [Data]) -> Data { tagged(0x30, parts.reduce(Data(), +)) }

    /// The DER body of the SHA-256 OID, 2.16.840.1.101.3.4.2.1.
    static let sha256OID: [UInt8] = [0x60, 0x86, 0x48, 0x01, 0x65, 0x03, 0x04, 0x02, 0x01]

    private static func tagged(_ tag: UInt8, _ body: Data) -> Data {
        Data([tag]) + length(body.count) + body
    }

    /// Definite-length encoding: short form below 128, long form above.
    static func length(_ count: Int) -> Data {
        if count < 0x80 { return Data([UInt8(count)]) }
        var bytes: [UInt8] = []
        var remaining = count
        while remaining > 0 {
            bytes.insert(UInt8(remaining & 0xFF), at: 0)
            remaining >>= 8
        }
        return Data([0x80 | UInt8(bytes.count)] + bytes)
    }

    // MARK: Parsing

    struct Element {
        let tag: UInt8
        let body: Data
        /// Offset just past this element in its parent.
        let end: Int
    }

    /// Reads one element beginning at `offset`.
    static func element(in data: Data, at offset: Int) -> Element? {
        var index = offset
        guard index < data.count else { return nil }
        let tag = data[data.startIndex + index]
        index += 1
        guard index < data.count else { return nil }

        var length = Int(data[data.startIndex + index])
        index += 1
        if length & 0x80 != 0 {
            let byteCount = length & 0x7F
            guard byteCount > 0, byteCount <= 4, index + byteCount <= data.count else { return nil }
            length = 0
            for _ in 0..<byteCount {
                length = (length << 8) | Int(data[data.startIndex + index])
                index += 1
            }
        }

        guard index + length <= data.count else { return nil }
        let start = data.startIndex + index
        return Element(tag: tag, body: data[start..<(start + length)], end: index + length)
    }
}
