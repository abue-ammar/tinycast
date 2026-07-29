import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        AppCore.shared.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Tear down the Hyper Key input hooks and restore Caps Lock before the process exits.
        AppCore.shared.hyperKeyTap.prepareForTermination()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        AppCore.shared.handleReopen()
        return true
    }
}
