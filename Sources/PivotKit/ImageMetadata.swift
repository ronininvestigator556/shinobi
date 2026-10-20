// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Reads an image's embedded metadata.
///
/// ImageIO rather than a JavaScript EXIF parser: it handles every format the system knows —
/// JPEG, HEIC, PNG, TIFF, RAW — including the maker-note dialects that a hand-written parser
/// gets wrong, and it is the same code path Preview uses, so what Shinobi reports is what an
/// examiner will see when they open the file themselves.
public enum ImageMetadata {

    public struct Reading: Sendable {
        public var sourceURL: URL
        public var pixelSize: String?
        public var fileType: String?
        public var byteCount: Int
        /// Ordered sections of name/value pairs, ready to display.
        public var sections: [(title: String, values: [(String, String)])]
        /// Where the photograph was taken, when the file says.
        public var coordinate: (latitude: Double, longitude: Double)?
        public var hasMetadata: Bool { !sections.isEmpty }
    }

    /// Fetches the image through `session` and reads what is embedded in it.
    ///
    /// The fetch goes through the caller's session so it uses the active container's egress —
    /// pulling a subject's image over the machine's own connection would disclose the
    /// investigator's address for the sake of reading a timestamp.
    public static func read(from url: URL, using session: URLSession) async throws -> Reading {
        let (data, _) = try await session.data(from: url)
        return read(data: data, url: url)
    }

    public static func read(data: Data, url: URL) -> Reading {
        var reading = Reading(
            sourceURL: url,
            pixelSize: nil,
            fileType: nil,
            byteCount: data.count,
            sections: [],
            coordinate: nil
        )

        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return reading }

        if let type = CGImageSourceGetType(source) as String? {
            reading.fileType = UTType(type)?.localizedDescription ?? type
        }

        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)
            as? [CFString: Any] else { return reading }

        if let width = properties[kCGImagePropertyPixelWidth] as? Int,
           let height = properties[kCGImagePropertyPixelHeight] as? Int {
            reading.pixelSize = "\(width) × \(height)"
        }

        // Only the dictionaries an investigator actually reads. The full property set runs to
        // hundreds of entries, most of them colour-management detail that buries the four or
        // five lines that matter.
        let interesting: [(CFString, String)] = [
            (kCGImagePropertyExifDictionary, "EXIF"),
            (kCGImagePropertyGPSDictionary, "GPS"),
            (kCGImagePropertyTIFFDictionary, "Camera"),
            (kCGImagePropertyIPTCDictionary, "IPTC"),
        ]

        for (key, title) in interesting {
            guard let dictionary = properties[key] as? [CFString: Any], !dictionary.isEmpty else {
                continue
            }
            let values = dictionary
                .map { (readableName($0.key), String(describing: $0.value)) }
                .sorted { $0.0 < $1.0 }
            reading.sections.append((title: title, values: values))
        }

        reading.coordinate = coordinate(from: properties)
        return reading
    }

    /// Latitude and longitude, with the hemisphere references applied.
    ///
    /// EXIF stores the magnitude and the hemisphere separately; ignoring the reference is a
    /// classic way to place a photograph in the wrong hemisphere entirely.
    private static func coordinate(from properties: [CFString: Any]) -> (Double, Double)? {
        guard let gps = properties[kCGImagePropertyGPSDictionary] as? [CFString: Any],
              let latitude = gps[kCGImagePropertyGPSLatitude] as? Double,
              let longitude = gps[kCGImagePropertyGPSLongitude] as? Double
        else { return nil }

        let latitudeRef = gps[kCGImagePropertyGPSLatitudeRef] as? String ?? "N"
        let longitudeRef = gps[kCGImagePropertyGPSLongitudeRef] as? String ?? "E"
        return (
            latitudeRef.uppercased() == "S" ? -latitude : latitude,
            longitudeRef.uppercased() == "W" ? -longitude : longitude
        )
    }

    /// Turns `kCGImagePropertyExifDateTimeOriginal` into "Date Time Original".
    private static func readableName(_ key: CFString) -> String {
        var name = key as String
        for prefix in ["kCGImageProperty", "Exif", "GPS", "TIFF", "IPTC"] {
            if name.hasPrefix(prefix) { name = String(name.dropFirst(prefix.count)) }
        }
        var spaced = ""
        for character in name {
            if character.isUppercase, !spaced.isEmpty, spaced.last != " " { spaced.append(" ") }
            spaced.append(character)
        }
        return spaced.isEmpty ? (key as String) : spaced
    }
}
