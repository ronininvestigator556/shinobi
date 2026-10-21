// SPDX-License-Identifier: GPL-3.0-or-later
import ShinobiKit
import PivotKit
import SwiftUI

/// Shows what is embedded in an image.
struct ImageMetadataView: View {

    let reading: ImageMetadata.Reading
    let onOpenMap: (URL) -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text(reading.sourceURL.lastPathComponent.isEmpty
                     ? reading.sourceURL.absoluteString
                     : reading.sourceURL.lastPathComponent)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                Text([reading.fileType, reading.pixelSize,
                      ByteCountFormatter.string(fromByteCount: Int64(reading.byteCount), countStyle: .file)]
                        .compactMap { $0 }.joined(separator: " · "))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .padding(12)

            Divider()

            if let coordinate = reading.coordinate {
                HStack {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Location recorded in the file")
                            .font(.system(size: 12, weight: .medium))
                        Text(String(format: "%.6f, %.6f", coordinate.latitude, coordinate.longitude))
                            .font(.system(size: 12, design: .monospaced))
                            .textSelection(.enabled)
                    }
                    Spacer()
                    Button("Open in Maps") {
                        let query = "\(coordinate.latitude),\(coordinate.longitude)"
                        if let url = URL(string: "https://www.openstreetmap.org/?mlat=\(coordinate.latitude)&mlon=\(coordinate.longitude)#map=16/\(query)") {
                            onOpenMap(url)
                        }
                    }
                }
                .padding(12)
                .background(Color(Palette.statusCapture).opacity(0.12))
                Divider()
            }

            if reading.hasMetadata {
                List {
                    ForEach(reading.sections, id: \.title) { section in
                        Section(section.title) {
                            ForEach(section.values, id: \.0) { name, value in
                                HStack(alignment: .top) {
                                    Text(name)
                                        .font(.system(size: 11))
                                        .foregroundStyle(.secondary)
                                        .frame(width: 190, alignment: .leading)
                                    Text(value)
                                        .font(.system(size: 11, design: .monospaced))
                                        .textSelection(.enabled)
                                }
                            }
                        }
                    }
                }
                .listStyle(.inset)
            } else {
                VStack(spacing: 6) {
                    Spacer()
                    Text("No embedded metadata")
                        .font(.system(size: 12, weight: .medium))
                    // Absence is a finding, not a failure — most social platforms strip EXIF
                    // on upload, so a bare image is evidence of where it has been.
                    Text("Nothing is embedded in this file. Many platforms strip metadata when "
                         + "an image is uploaded, so this is common and is itself informative.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 380)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            }

            Divider()
            HStack {
                Spacer()
                Button("Done", action: onClose).keyboardShortcut(.cancelAction)
            }
            .padding(12)
        }
        .frame(width: 620, height: 560)
    }
}
