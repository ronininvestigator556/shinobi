// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import Testing

@testable import CaseKit

/// The dossier is the running index of who/what a case is about. Its one hard rule is that
/// the same entity seen twice is counted, not duplicated — otherwise "mentioned twenty times"
/// becomes twenty rows and the signal is lost.
@Suite("Case dossier")
struct DossierTests {

    private func makeStore() throws -> CaseStore {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("dossier-\(UUID().uuidString).shinobicase")
        let bundle = try CaseBundle.create(at: url)
        let store = try CaseStore(bundle: bundle, keyStore: EphemeralKeyStore())
        try store.initialise(name: "Test", reference: nil)
        return store
    }

    @Test("Entities are deduplicated by kind and normalised, counting occurrences")
    func dedupes() throws {
        let store = try makeStore()
        let first = try store.recordEntities([
            HarvestedEntity(kind: "email", value: "A@B.com", normalised: "a@b.com"),
            HarvestedEntity(kind: "domain", value: "X.com", normalised: "x.com"),
        ])
        #expect(first == 2)

        let second = try store.recordEntities([
            HarvestedEntity(kind: "email", value: "a@b.com", normalised: "a@b.com"),
        ])
        #expect(second == 0)

        let dossier = try store.dossier()
        #expect(dossier.count == 2)
        let email = dossier.first { $0.kind == "email" }
        #expect(email?.occurrences == 2)
        #expect(email?.value == "A@B.com")   // keeps the first-seen form
    }

    @Test("An empty harvest records nothing")
    func emptyHarvest() throws {
        let store = try makeStore()
        #expect(try store.recordEntities([]) == 0)
        #expect(try store.dossier().isEmpty)
    }

    @Test("Same value, different kind, is a distinct entity")
    func kindDistinguishes() throws {
        let store = try makeStore()
        _ = try store.recordEntities([
            HarvestedEntity(kind: "domain", value: "x.com", normalised: "x.com"),
            HarvestedEntity(kind: "username", value: "x.com", normalised: "x.com"),
        ])
        #expect(try store.dossier().count == 2)
    }
}
