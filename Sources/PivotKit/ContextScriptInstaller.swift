// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import WebKit

/// Installs the context-menu reporting script on a content controller exactly once.
///
/// Exists because getting this wrong is silent and severe. A container's
/// `WKUserContentController` is shared by every tab in it, so that a compiled blocking list can
/// be applied to tabs already open. `WKUserContentController.add(_:name:)` raises an
/// Objective-C exception when the same name is registered twice — and an Objective-C exception
/// cannot be caught in Swift. Registering per tab therefore meant the second tab in a container
/// threw during construction, the exception unwound through the initialiser, AppKit swallowed
/// it, and new tabs simply stopped appearing. No error, no log, nothing to search for.
///
/// Tracking which controllers are already prepared is a small thing, so it lives somewhere it
/// can be tested rather than inline in the window controller where it cannot.
@MainActor
public final class ContextScriptInstaller {

    private var prepared = Set<ObjectIdentifier>()

    public init() {}

    /// Installs the script and handler if this controller has not had them.
    ///
    /// - Returns: true when it installed, false when the controller was already prepared.
    @discardableResult
    public func install(
        on controller: WKUserContentController,
        handler: WKScriptMessageHandler
    ) -> Bool {
        guard prepared.insert(ObjectIdentifier(controller)).inserted else { return false }
        controller.addUserScript(ContextTarget.script)
        controller.add(handler, name: ContextTarget.messageName)
        return true
    }

    /// Forgets a controller, so a container whose session was destroyed can be set up again.
    public func forget(_ controller: WKUserContentController) {
        prepared.remove(ObjectIdentifier(controller))
    }

    public var preparedCount: Int { prepared.count }
}
