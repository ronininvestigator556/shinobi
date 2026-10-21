// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import Vision

/// Reads text out of images.
///
/// The reason this earns its place: a screenshot is pixels, so everything written in it is
/// invisible to a text index. A name that appears only in a banner, a phone number only in a
/// listing photograph, an address only in a scanned document — all of it is unsearchable
/// until something transcribes it. Running on device means the subject's images never leave
/// the machine to be read.
///
/// **A transcription is not the document.** OCR misreads, and it misreads confidently.
/// Everything here carries its confidence, and callers are expected to label the output as a
/// machine reading rather than as the page's own text.
public enum TextRecognition {

    public struct Recognition: Sendable, Equatable {
        public let text: String
        /// Mean confidence across the recognised lines, 0 to 1.
        public let confidence: Double
        public let lineCount: Int
        /// Languages Vision was asked to consider.
        public let languages: [String]

        public var isEmpty: Bool { text.isEmpty }

        /// A caveat to store alongside the transcription, so the caveat cannot be separated
        /// from the text it applies to.
        public var note: String {
            let percentage = Int((confidence * 100).rounded())
            return "Machine transcription of an image, not the page's own text. "
                + "\(lineCount) line(s), mean confidence \(percentage)%."
        }
    }

    /// Recognises text in image data.
    ///
    /// `.accurate` rather than `.fast`: this runs once per captured screenshot, not per frame,
    /// and a transcription that has to be re-read by a human to be trusted has not saved
    /// anyone anything.
    public static func recognise(
        in imageData: Data,
        languages: [String] = ["en-US"]
    ) throws -> Recognition {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = languages
        // Small text matters here — a watermark, a licence plate, a caption — and the default
        // floor discards exactly those.
        request.minimumTextHeight = 0.005

        let handler = VNImageRequestHandler(data: imageData, options: [:])
        try handler.perform([request])

        guard let observations = request.results, !observations.isEmpty else {
            return Recognition(text: "", confidence: 0, lineCount: 0, languages: languages)
        }

        var lines: [String] = []
        var total = 0.0
        for observation in observations {
            guard let candidate = observation.topCandidates(1).first else { continue }
            lines.append(candidate.string)
            total += Double(candidate.confidence)
        }

        return Recognition(
            text: lines.joined(separator: "\n"),
            confidence: lines.isEmpty ? 0 : total / Double(lines.count),
            lineCount: lines.count,
            languages: languages
        )
    }

    /// Languages Vision can recognise on this machine, for the language picker.
    public static func supportedLanguages() -> [String] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        return (try? request.supportedRecognitionLanguages()) ?? ["en-US"]
    }
}
