// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import Testing
import WebKit

@testable import PivotKit

/// The regression guard for a bug that presented as "new tabs sometimes do not open".
///
/// A container's content controller is shared by all its tabs so that blocking rules reach
/// tabs already open. Registering a script message handler per tab meant the second tab in a
/// container called `add(_:name:)` with a name already taken, which raises an Objective-C
/// exception — uncatchable in Swift, swallowed by AppKit, and leaving no trace beyond tabs
/// quietly failing to appear.
@Suite("Context script installation", .serialized)
@MainActor
struct ContextScriptInstallerTests {

    private final class Handler: NSObject, WKScriptMessageHandler {
        nonisolated func userContentController(
            _ controller: WKUserContentController, didReceive message: WKScriptMessage) {}
    }

    @Test("A controller is prepared once, however many tabs ask")
    func installsOnlyOnce() {
        let installer = ContextScriptInstaller()
        let controller = WKUserContentController()
        let handler = Handler()

        #expect(installer.install(on: controller, handler: handler))
        // Every subsequent tab in the same container must be a no-op. Doing the work again is
        // not merely wasteful — the second registration throws.
        for _ in 0..<10 {
            #expect(!installer.install(on: controller, handler: handler))
        }
        #expect(controller.userScripts.count == 1)
    }

    @Test("Separate containers are prepared separately")
    func distinctControllersAreDistinct() {
        let installer = ContextScriptInstaller()
        let handler = Handler()
        let first = WKUserContentController()
        let second = WKUserContentController()

        #expect(installer.install(on: first, handler: handler))
        #expect(installer.install(on: second, handler: handler))
        #expect(installer.preparedCount == 2)
        #expect(first.userScripts.count == 1)
        #expect(second.userScripts.count == 1)
    }

    @Test("A forgotten controller can be prepared again")
    func forgettingAllowsReinstall() {
        // A container whose session is destroyed and rebuilt gets a fresh controller; the
        // installer must not treat the old identity as still prepared.
        let installer = ContextScriptInstaller()
        let controller = WKUserContentController()
        let handler = Handler()

        #expect(installer.install(on: controller, handler: handler))
        installer.forget(controller)
        controller.removeAllUserScripts()
        controller.removeScriptMessageHandler(forName: ContextTarget.messageName)
        #expect(installer.install(on: controller, handler: handler))
    }

    @Test("Scripts do not accumulate across many tabs")
    func scriptsDoNotAccumulate() {
        // The milder half of the same bug: every tab also added another copy of the script,
        // so a container with twenty tabs ran twenty context listeners on every page.
        let installer = ContextScriptInstaller()
        let controller = WKUserContentController()
        let handler = Handler()
        for _ in 0..<20 { installer.install(on: controller, handler: handler) }
        #expect(controller.userScripts.count == 1)
    }
}
