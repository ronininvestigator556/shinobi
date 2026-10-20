// SPDX-License-Identifier: GPL-3.0-or-later
import AppKit

// Shinobi is built as a SwiftPM executable and bundled by `Scripts/build-app.sh`, so the
// entry point is explicit rather than `@main` on the delegate.
let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
application.setActivationPolicy(.regular)
application.run()
