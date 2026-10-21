// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import Testing

@testable import IdentityKit

/// Behavioural blocking's whole claim is "seen across enough distinct sites = tracker". These
/// pin exactly where that line is, since getting it wrong either blocks a site's own CDN or
/// lets a real tracker through.
@Suite("Behavioural learner")
struct BehaviorLearnerTests {

    private func learner(threshold: Int = 3) -> BehaviorLearner {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("beh-\(UUID().uuidString).json")
        return BehaviorLearner(threshold: threshold, fileURL: url)
    }

    @Test("A third party under the threshold is not yet a tracker")
    func belowThreshold() {
        let learner = learner(threshold: 3)
        learner.observe(firstParty: "a.com", thirdParties: ["track.io"])
        learner.observe(firstParty: "b.com", thirdParties: ["track.io"])
        #expect(learner.trackers().isEmpty)
    }

    @Test("Crossing the threshold of distinct sites promotes a tracker")
    func crossesThreshold() {
        let learner = learner(threshold: 3)
        #expect(learner.observe(firstParty: "a.com", thirdParties: ["track.io"]) == false)
        #expect(learner.observe(firstParty: "b.com", thirdParties: ["track.io"]) == false)
        #expect(learner.observe(firstParty: "c.com", thirdParties: ["track.io"]) == true)   // promoted
        #expect(learner.trackers() == ["track.io"])
    }

    @Test("The same site seen repeatedly does not inflate the count")
    func sameSiteDoesNotInflate() {
        let learner = learner(threshold: 3)
        for _ in 0..<10 { learner.observe(firstParty: "a.com", thirdParties: ["track.io"]) }
        #expect(learner.trackers().isEmpty)
    }

    @Test("A domain never counts itself as its own third party")
    func ignoresSelf() {
        let learner = learner(threshold: 2)
        learner.observe(firstParty: "a.com", thirdParties: ["a.com"])
        learner.observe(firstParty: "a.com", thirdParties: ["a.com"])
        #expect(learner.trackers().isEmpty)
    }

    @Test("What was learned survives a reload")
    func persists() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("beh-persist-\(UUID().uuidString).json")
        let first = BehaviorLearner(threshold: 2, fileURL: url)
        first.observe(firstParty: "a.com", thirdParties: ["track.io"])
        first.observe(firstParty: "b.com", thirdParties: ["track.io"])
        #expect(first.trackers() == ["track.io"])

        let reopened = BehaviorLearner(threshold: 2, fileURL: url)
        #expect(reopened.trackers() == ["track.io"])
    }

    @Test("Reset forgets everything")
    func reset() {
        let learner = learner(threshold: 2)
        learner.observe(firstParty: "a.com", thirdParties: ["track.io"])
        learner.observe(firstParty: "b.com", thirdParties: ["track.io"])
        learner.reset()
        #expect(learner.trackers().isEmpty)
    }
}
