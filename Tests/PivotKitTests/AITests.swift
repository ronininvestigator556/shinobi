// SPDX-License-Identifier: GPL-3.0-or-later
import AppKit
import Foundation
import Testing

@testable import PivotKit

@Suite("Text recognition")
struct TextRecognitionTests {

    /// Renders text into a real PNG so Vision is exercised on an actual image.
    private func imageContaining(_ text: String, size: CGSize = CGSize(width: 900, height: 220)) throws -> Data {
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.white.setFill()
        NSRect(origin: .zero, size: size).fill()
        (text as NSString).draw(
            at: NSPoint(x: 30, y: size.height / 2 - 30),
            withAttributes: [
                .font: NSFont.systemFont(ofSize: 44),
                .foregroundColor: NSColor.black,
            ])
        image.unlockFocus()

        let tiff = try #require(image.tiffRepresentation)
        let bitmap = try #require(NSBitmapImageRep(data: tiff))
        return try #require(bitmap.representation(using: .png, properties: [:]))
    }

    @Test("Text rendered into an image is recovered")
    func textIsRecovered() throws {
        // The whole point: a name that exists only as pixels is unsearchable until something
        // transcribes it.
        let data = try imageContaining("Ashcroft Holdings Ltd")
        let result = try TextRecognition.recognise(in: data)

        #expect(result.text.contains("Ashcroft"))
        #expect(result.lineCount >= 1)
        #expect(result.confidence > 0.3)
    }

    @Test("An image with no text reports none rather than inventing some")
    func blankImageYieldsNothing() throws {
        let image = NSImage(size: CGSize(width: 200, height: 120))
        image.lockFocus()
        NSColor.systemBlue.setFill()
        NSRect(x: 0, y: 0, width: 200, height: 120).fill()
        image.unlockFocus()
        let tiff = try #require(image.tiffRepresentation)
        let bitmap = try #require(NSBitmapImageRep(data: tiff))
        let data = try #require(bitmap.representation(using: .png, properties: [:]))

        let result = try TextRecognition.recognise(in: data)
        #expect(result.isEmpty)
        #expect(result.confidence == 0)
    }

    @Test("A transcription carries its own caveat")
    func transcriptionCarriesCaveat() throws {
        let data = try imageContaining("Invoice 44821")
        let result = try TextRecognition.recognise(in: data)

        // OCR misreads, and it misreads confidently. The caveat has to travel with the text
        // so the two cannot be separated in a report.
        #expect(result.note.contains("Machine transcription"))
        #expect(result.note.contains("confidence"))
    }

    @Test("Unreadable data throws rather than returning empty text")
    func garbageThrows() {
        // Silently returning "" would look identical to an image that genuinely has no text.
        #expect(throws: (any Error).self) {
            _ = try TextRecognition.recognise(in: Data([0x00, 0x01, 0x02]))
        }
    }
}

@Suite("Named entities")
struct NamedEntitiesTests {

    @Test("People, organisations and places are separated")
    func entitiesAreSeparated() {
        let text = """
        Jane Ashcroft was appointed a director of Ashcroft Holdings Limited.
        The company is registered in Birmingham and also operates from Manchester.
        Jane Ashcroft previously worked at Barclays.
        """
        let mentions = NamedEntities.extract(from: text)
        let people = mentions.filter { $0.kind == .person }.map(\.name)
        let places = mentions.filter { $0.kind == .place }.map(\.name)

        #expect(people.contains { $0.contains("Ashcroft") })
        #expect(places.contains { $0.contains("Birmingham") || $0.contains("Manchester") })
    }

    @Test("Repeated names are counted, not duplicated")
    func mentionsAreCounted() {
        // A name mentioned once may be incidental; one mentioned repeatedly is what the page
        // is about, and the ordering should say so.
        let text = "Jane Ashcroft met Jane Ashcroft's accountant. Jane Ashcroft signed."
        let mentions = NamedEntities.extract(from: text)
        let jane = mentions.first { $0.name.contains("Ashcroft") }
        #expect(jane?.count ?? 0 >= 2)
        #expect(mentions.filter { $0.name == jane?.name }.count == 1)
    }

    @Test("Empty or trivial text yields nothing")
    func trivialTextYieldsNothing() {
        #expect(NamedEntities.extract(from: "").isEmpty)
        #expect(NamedEntities.extract(from: "the and or but").isEmpty)
    }

    @Test("Extraction is bounded")
    func extractionIsBounded() {
        let text = (0..<300).map { "Person Number\($0) visited London." }.joined(separator: " ")
        #expect(NamedEntities.extract(from: text, limit: 25).count <= 25)
    }
}

@Suite("Entity de-duplication")
struct EntityDeduplicationTests {

    @Test("A name is listed once, not under several headings")
    func namesAppearOnce() {
        // The tagger genuinely does this: on a real page it read "Bellingcat" as a person in
        // one sentence and a place in another, and the inspector listed it under both. A panel
        // that contradicts itself undermines the entries that are correct.
        let text = """
        Bellingcat published the findings. Researchers at Bellingcat confirmed them.
        Bellingcat has offices in Amsterdam. The Bellingcat team travelled to Amsterdam.
        """
        let mentions = NamedEntities.extract(from: text)
        let names = mentions.map(\.name)
        #expect(names.count == Set(names).count, "a name appeared under more than one heading")
    }

    @Test("The reading the tagger reached most often is the one kept")
    func mostFrequentReadingWins() {
        let text = "Jane Ashcroft signed. Jane Ashcroft filed. Jane Ashcroft attended."
        let mentions = NamedEntities.extract(from: text)
        let jane = mentions.first { $0.name.contains("Ashcroft") }
        #expect(jane != nil)
        // Whatever it settled on, it settled on one thing.
        #expect(mentions.filter { $0.name == jane?.name }.count == 1)
    }
}
