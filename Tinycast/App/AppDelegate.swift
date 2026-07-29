import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var shouldStart = true

    func applicationWillFinishLaunching(_ notification: Notification) {
        guard let bundleIdentifier = Bundle.main.bundleIdentifier else { return }
        let existing = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
            .first { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
        guard let existing else { return }
        shouldStart = false
        existing.activate()
        NSApp.terminate(nil)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard shouldStart else { return }
        AppCore.shared.start()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        AppCore.shared.applicationShouldTerminate()
    }

    func applicationWillTerminate(_ notification: Notification) {
        AppCore.shared.prepareForTermination()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        AppCore.shared.handleReopen()
        return true
    }
}
