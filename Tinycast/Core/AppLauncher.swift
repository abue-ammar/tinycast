import AppKit

enum AppLauncher {

    @MainActor
    static func launch(_ url: URL) {
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    @MainActor
    static func showInFinder(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    /// Opens System Settings at the pane backed by the given extension bundle ID.
    @MainActor
    static func openSettingsPane(bundleID: String) {
        guard let url = URL(string: "x-apple.systempreferences:" + bundleID) else { return }
        NSWorkspace.shared.open(url)
    }

    /// Focus the app if it isn't frontmost, hide it if it is, launch it if it isn't running.
    @MainActor
    static func toggle(bundleID: String) {
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .first
        if let running, running.isActive {
            running.hide()
            return
        }
        if let url = running?.bundleURL
            ?? NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
        {
            // Dock-click semantics: activates, raises, unhides, and reopens a window — none of which a bare `activate()` reliably does under cooperative activation (macOS 14+).
            NSWorkspace.shared.openApplication(
                at: url, configuration: NSWorkspace.OpenConfiguration())
        } else if let running {
            // Running app whose bundle URL can't be resolved (moved or deleted since launch).
            running.unhide()
            running.activate()
        }
    }

    /// Asks every running instance of a bundle ID to quit — graceful, so an app with unsaved work still gets to put its own sheet up. False when nothing was running.
    @MainActor
    @discardableResult
    static func quit(bundleID: String) -> Bool {
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
        for app in running { app.terminate() }
        return !running.isEmpty
    }

    /// Finder is never a Quit All target: `terminate()` only makes it relaunch, and nobody means the desktop when they say "quit everything".
    private static let quitAllExclusions: Set<String> = ["com.apple.finder"]

    /// What Quit All acts on: every app with a Dock presence, minus Finder and Tinycast itself. Accessories and background agents are left alone. The caller resolves this once and terminates that same list, so the set it confirms is the set it quits.
    @MainActor
    static func quitAllTargets() -> [NSRunningApplication] {
        // Excluded by PID, not by activation policy: About/Settings temporarily flips Tinycast to `.regular`, which a policy-only filter would read as a target.
        let ownPID = NSRunningApplication.current.processIdentifier
        return NSWorkspace.shared.runningApplications.filter { app in
            app.activationPolicy == .regular
                && app.processIdentifier != ownPID
                && !quitAllExclusions.contains(app.bundleIdentifier ?? "")
        }
    }
}
