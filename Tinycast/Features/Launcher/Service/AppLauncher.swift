import AppKit

enum AppLauncher {

    @MainActor
    static func launch(_ url: URL) {
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    /// Hands the URL to whatever the system registers for its scheme — the default browser, for web.
    @MainActor
    static func open(_ url: URL) {
        NSWorkspace.shared.open(url)
    }

    @MainActor
    static func showInFinder(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    /// No AppKit route for Get Info, so this drives Finder over Apple events — seconds when cold.
    static func showInfoInFinder(_ url: URL) async -> Bool {
        let source = """
            tell application "Finder"
                activate
                open information window of (POSIX file "\(url.path)" as alias)
            end tell
            """
        return await Task.detached(priority: .userInitiated) {
            guard let script = NSAppleScript(source: source) else { return false }
            var errorInfo: NSDictionary?
            script.executeAndReturnError(&errorInfo)
            return errorInfo == nil
        }.value
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
            // Dock-click semantics; a bare `activate()` does none of it reliably.
            NSWorkspace.shared.openApplication(
                at: url, configuration: NSWorkspace.OpenConfiguration())
        } else if let running {
            // Running app whose bundle URL can't be resolved (moved or deleted since launch).
            running.unhide()
            running.activate()
        }
    }

    /// Asks every instance to quit, gracefully, so unsaved work still gets its sheet.
    @MainActor
    @discardableResult
    static func quit(bundleID: String) -> Bool {
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
        for app in running { app.terminate() }
        return !running.isEmpty
    }

    /// Long enough for any app to exit, short enough not to relaunch under the user.
    private static let exitGrace = Duration.seconds(5)

    /// A refused quit — a save sheet left standing — relaunches nothing.
    @MainActor
    static func restart(bundleID: String, url: URL) async {
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
        guard !running.isEmpty, await quitAwaitingExit(running) else { return }
        launch(url)
    }

    /// Observes before it terminates, so an instance that exits at once can't outrun the wait.
    @MainActor
    private static func quitAwaitingExit(_ apps: [NSRunningApplication]) async -> Bool {
        let center = NSWorkspace.shared.notificationCenter
        let (exits, continuation) = AsyncStream.makeStream(of: pid_t.self)
        let observer = center.addObserver(
            of: NSWorkspace.shared, for: NSWorkspace.DidTerminateApplicationMessage.self
        ) { continuation.yield($0.application.processIdentifier) }
        defer { center.removeObserver(observer) }

        var pending = Set(apps.map(\.processIdentifier))
        for app in apps { app.terminate() }

        let grace = Task {
            try? await Task.sleep(for: exitGrace); continuation.finish()
        }
        defer { grace.cancel() }
        for await pid in exits {
            pending.remove(pid)
            if pending.isEmpty { return true }
        }
        return false
    }

    /// Finder is never a Quit All target: `terminate()` only makes it relaunch.
    private static let quitAllExclusions: Set<String> = ["com.apple.finder"]

    /// Every app with a Dock presence, bar Finder and us; resolved once, so it can't drift.
    @MainActor
    static func quitAllTargets() -> [NSRunningApplication] {
        // By PID, not policy: About/Settings flips us to `.regular` temporarily.
        let ownPID = NSRunningApplication.current.processIdentifier
        return NSWorkspace.shared.runningApplications.filter { app in
            app.activationPolicy == .regular
                && app.processIdentifier != ownPID
                && !quitAllExclusions.contains(app.bundleIdentifier ?? "")
        }
    }
}
