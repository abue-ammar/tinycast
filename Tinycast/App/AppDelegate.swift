import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private enum TerminationState { case idle, preparing, ready }
    private var terminationState = TerminationState.idle

    /// Must land before the first scroll view exists, or the scroller switch shows as a flash.
    func applicationWillFinishLaunching(_ notification: Notification) {
        UserDefaults.standard.set("WhenScrolling", forKey: "AppleShowScrollBars")
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppCore.shared.start()
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            AppCore.shared.handleOpenURL(url)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        // The Hyper Key's HID-level caps remap outlives the process; give the key back.
        AppCore.shared.prepareForTermination()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        switch terminationState {
        case .ready: return .terminateNow
        case .preparing: return .terminateCancel
        case .idle: break
        }
        // The Dock icon only stands for the open windows, so its Quit closes them, not the agent.
        let activation = AppCore.shared.activationPolicy
        if isQuitFromDock, activation.hasOpenWindows {
            activation.closeAll()
            return .terminateCancel
        }
        terminationState = .preparing
        Task { @MainActor in
            await AppCore.shared.stopDictationForTermination()
            // A 300 ms-debounced draft still has to reach disk, but it can no longer veto the quit.
            await AppCore.shared.flushNotesForTermination()
            terminationState = .ready
            sender.terminate(nil)
        }
        // AppKit's terminateLater loop cannot resume MainActor tasks used by cleanup.
        return .terminateCancel
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        AppCore.shared.handleReopen()
        return true
    }

    /// The palette and Settings each close on their own; the agent outlives both.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// ⌘Q and the menu-bar item call `terminate` directly; only an Apple Event names a sender.
    private var isQuitFromDock: Bool {
        guard let event = NSAppleEventManager.shared().currentAppleEvent,
            event.eventClass == kCoreEventClass, event.eventID == kAEQuitApplication,
            let pid = event.attributeDescriptor(forKeyword: keySenderPIDAttr)?.int32Value
        else { return false }
        return NSRunningApplication(processIdentifier: pid)?.bundleIdentifier == "com.apple.dock"
    }
}
