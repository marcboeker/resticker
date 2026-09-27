import AppKit

// `AppDelegate` is `@MainActor` (it owns AppKit UI and the Settings window's SwiftUI
// model), so top-level code needs to assert it is already running on the main thread -
// which it is: this is the process's initial thread, and NSApplication requires it.
MainActor.assumeIsolated {
    let delegate = AppDelegate()
    let application = NSApplication.shared
    application.delegate = delegate
    application.setActivationPolicy(.accessory)
    application.run()
}
