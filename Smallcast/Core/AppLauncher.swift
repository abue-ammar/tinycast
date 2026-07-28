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
}
