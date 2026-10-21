// SPDX-License-Identifier: GPL-3.0-or-later
import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers

@testable import PivotKit

@Suite("Image metadata")
struct ImageMetadataTests {

    /// Builds a real JPEG carrying the given properties, so the reader is exercised against
    /// ImageIO rather than against a stand-in.
    private func makeJPEG(properties: [CFString: Any] = [:]) throws -> Data {
        let width = 8, height = 8
        let context = try #require(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = try #require(context.makeImage())

        let output = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(
            output, UTType.jpeg.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        #expect(CGImageDestinationFinalize(destination))
        return output as Data
    }

    private let url = URL(string: "https://example.com/photo.jpg")!

    @Test("Basic properties are read")
    func basicPropertiesAreRead() throws {
        let reading = ImageMetadata.read(data: try makeJPEG(), url: url)
        #expect(reading.pixelSize == "8 × 8")
        #expect(reading.byteCount > 0)
        #expect(reading.fileType != nil)
    }

    @Test("An image with no metadata reports none rather than failing")
    func bareImageIsHandled() throws {
        // Absence is a finding: most platforms strip EXIF on upload, so a bare image says
        // something about where it has been.
        let reading = ImageMetadata.read(data: try makeJPEG(), url: url)
        #expect(reading.coordinate == nil)
    }

    @Test("EXIF fields are surfaced")
    func exifIsSurfaced() throws {
        let data = try makeJPEG(properties: [
            kCGImagePropertyExifDictionary: [
                kCGImagePropertyExifDateTimeOriginal: "2026:09:08 11:22:33",
            ] as CFDictionary,
            kCGImagePropertyTIFFDictionary: [
                kCGImagePropertyTIFFMake: "TestCam",
            ] as CFDictionary,
        ])
        let reading = ImageMetadata.read(data: data, url: url)

        let exif = try #require(reading.sections.first { $0.title == "EXIF" })
        #expect(exif.values.contains { $0.1.contains("2026:09:08") })

        let camera = try #require(reading.sections.first { $0.title == "Camera" })
        #expect(camera.values.contains { $0.1 == "TestCam" })
    }

    @Test("Property names are made readable")
    func namesAreReadable() throws {
        let data = try makeJPEG(properties: [
            kCGImagePropertyExifDictionary: [
                kCGImagePropertyExifDateTimeOriginal: "2026:09:08 11:22:33",
            ] as CFDictionary,
        ])
        let reading = ImageMetadata.read(data: data, url: url)
        let exif = try #require(reading.sections.first { $0.title == "EXIF" })

        // "kCGImagePropertyExifDateTimeOriginal" is not something to put in front of someone.
        #expect(exif.values.contains { $0.0 == "Date Time Original" })
    }

    @Test("Northern and eastern coordinates are positive")
    func northEastCoordinates() throws {
        let data = try makeJPEG(properties: [
            kCGImagePropertyGPSDictionary: [
                kCGImagePropertyGPSLatitude: 52.5200,
                kCGImagePropertyGPSLatitudeRef: "N",
                kCGImagePropertyGPSLongitude: 13.4050,
                kCGImagePropertyGPSLongitudeRef: "E",
            ] as CFDictionary,
        ])
        let coordinate = try #require(ImageMetadata.read(data: data, url: url).coordinate)
        #expect(abs(coordinate.latitude - 52.52) < 0.001)
        #expect(abs(coordinate.longitude - 13.405) < 0.001)
    }

    @Test("Southern and western coordinates are negated")
    func southWestCoordinates() throws {
        // EXIF stores the magnitude and the hemisphere separately. Ignoring the reference
        // puts the photograph in the wrong hemisphere — Rio de Janeiro would be read as a
        // point in Iraq — which is the kind of error that survives all the way into a report.
        let data = try makeJPEG(properties: [
            kCGImagePropertyGPSDictionary: [
                kCGImagePropertyGPSLatitude: 22.9068,
                kCGImagePropertyGPSLatitudeRef: "S",
                kCGImagePropertyGPSLongitude: 43.1729,
                kCGImagePropertyGPSLongitudeRef: "W",
            ] as CFDictionary,
        ])
        let coordinate = try #require(ImageMetadata.read(data: data, url: url).coordinate)
        #expect(coordinate.latitude < 0, "southern latitude was not negated")
        #expect(coordinate.longitude < 0, "western longitude was not negated")
        #expect(abs(coordinate.latitude + 22.9068) < 0.001)
        #expect(abs(coordinate.longitude + 43.1729) < 0.001)
    }

    @Test("Unreadable data does not crash the reader")
    func garbageIsHandled() {
        let reading = ImageMetadata.read(data: Data([0x00, 0x01, 0x02, 0x03]), url: url)
        #expect(!reading.hasMetadata)
        #expect(reading.pixelSize == nil)
    }
}

@Suite("Reverse image search")
struct ReverseImageSearchTests {

    @Test("Every engine produces a usable URL")
    func enginesProduceURLs() throws {
        let image = URL(string: "https://example.com/a b/photo.jpg?v=1&x=2")!
        for engine in ReverseImageSearch.engines {
            let url = try #require(engine.url(for: image), "\(engine.name) produced nothing")
            #expect(url.scheme == "https")
            // The image address is a parameter, so its own query must not leak into the
            // engine's.
            #expect(!url.absoluteString.contains("&x=2"))
        }
    }

    @Test("Images with no fetchable address are not offered", arguments: [
        "data:image/png;base64,iVBORw0KGgo=",
        "blob:https://example.com/8bf0a1",
        "file:///Users/someone/photo.jpg",
    ])
    func unfetchableImagesAreRejected(_ raw: String) throws {
        // A search engine cannot fetch these, so offering the lookup would produce a broken
        // page instead of a result.
        let url = try #require(URL(string: raw))
        for engine in ReverseImageSearch.engines {
            #expect(engine.url(for: url) == nil, "\(engine.name) accepted \(raw)")
        }
    }
}
