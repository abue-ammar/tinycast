import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var terminationRequestInFlight = false

    /// Must land before the first scroll view exists, or the scroller switch shows as a flash.
    func applicationWillFinishLaunching(_ notification: Notification) {
        UserDefaults.standard.set("WhenScrolling", forKey: "AppleShowScrollBars")
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppCore.shared.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        // The Hyper Key's HID-level caps remap outlives the process; give the key back.
        AppCore.shared.prepareForTermination()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !terminationRequestInFlight else { return .terminateLater }
        terminationRequestInFlight = true
        Task { @MainActor [weak self] in
            // A 300 ms-debounced draft still has to reach disk, but it can no longer veto the quit.
            await AppCore.shared.flushNotesForTermination()
            self?.terminationRequestInFlight = false
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        AppCore.shared.handleReopen()
        return true
    }

    /// The palette and Settings each close on their own; the agent outlives both.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
