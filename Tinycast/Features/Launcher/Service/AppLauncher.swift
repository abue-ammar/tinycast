import AppKit

enum AppLauncher {
    struct FileManagerSelection {
        let bundleID: String
        let appURL: URL?
        let name: String
        let followsSystem: Bool
        let configuredBundleID: String?
        let isConfiguredApplicationMissing: Bool

        var actionTitle: String {
            bundleID == FileViewerPolicy.finderBundleID
                ? String(localized: "Show in Finder")
                : String(localized: "Show in \(name)")
        }
    }

    private enum FileManagerAction {
        case reveal
        case openDirectory
    }

    @MainActor
    static func launch(_ url: URL, allowsRunningApplicationSubstitution: Bool = true) {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.allowsRunningApplicationSubstitution = allowsRunningApplicationSubstitution
        NSWorkspace.shared.openApplication(at: url, configuration: configuration)
    }

    @MainActor
    static func open(_ url: URL) {
        NSWorkspace.shared.open(url)
    }

    @MainActor
    static func showInFileManager(_ url: URL) {
        perform(url, action: .reveal, using: currentFileManager.bundleID)
    }

    @MainActor
    static func openDirectoryInFileManager(_ url: URL) {
        perform(url, action: .openDirectory, using: currentFileManager.bundleID)
    }

    @MainActor
    static var currentFileManager: FileManagerSelection {
        let configuredBundleID = UserDefaults.standard.string(
            forKey: FileViewerPolicy.configuredBundleIDKey)
        return fileManager(configuredBundleID: configuredBundleID)
    }

    @MainActor
    static func fileManager(configuredBundleID: String?) -> FileManagerSelection {
        let systemBundleID = UserDefaults.standard.string(
            forKey: FileViewerPolicy.systemFileViewerKey)
        let target = FileViewerPolicy.resolvedTarget(
            configuredBundleID: configuredBundleID, systemBundleID: systemBundleID,
            isAvailable: { applicationURL(for: $0) != nil })
        let appURL = applicationURL(for: target.bundleID)
        return FileManagerSelection(
            bundleID: target.bundleID,
            appURL: appURL,
            name: target == .finder
                ? String(localized: "Finder") : bundleName(at: appURL, bundleID: target.bundleID),
            followsSystem: normalizedBundleID(configuredBundleID) == nil,
            configuredBundleID: normalizedBundleID(configuredBundleID),
            isConfiguredApplicationMissing: FileViewerPolicy.isConfiguredApplicationMissing(
                configuredBundleID: configuredBundleID,
                isAvailable: { applicationURL(for: $0) != nil }))
    }

    @MainActor
    private static func perform(
        _ url: URL, action: FileManagerAction, using bundleID: String
    ) {
        let target =
            bundleID.caseInsensitiveCompare(FileViewerPolicy.finderBundleID) == .orderedSame
            ? FileViewerTarget.finder : .application(bundleID: bundleID)
        if target == .finder {
            openWithFinder(url, action: action)
            return
        }
        guard let appURL = applicationURL(for: bundleID) else {
            fallbackToSystem(url, action: action, failedBundleID: bundleID)
            return
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.open(
            [url], withApplicationAt: appURL, configuration: configuration
        ) { _, error in
            guard error != nil else { return }
            Task { @MainActor in
                fallbackToSystem(url, action: action, failedBundleID: bundleID)
            }
        }
    }

    @MainActor
    private static func fallbackToSystem(
        _ url: URL, action: FileManagerAction, failedBundleID: String
    ) {
        let systemBundleID = UserDefaults.standard.string(
            forKey: FileViewerPolicy.systemFileViewerKey)
        let systemTarget = FileViewerPolicy.resolvedTarget(
            configuredBundleID: nil, systemBundleID: systemBundleID,
            isAvailable: { applicationURL(for: $0) != nil })
        if systemTarget.bundleID != failedBundleID {
            perform(url, action: action, using: systemTarget.bundleID)
            return
        }
        openWithFinder(url, action: action)
    }

    @MainActor
    private static func openWithFinder(_ url: URL, action: FileManagerAction) {
        switch action {
        case .reveal:
            NSWorkspace.shared.activateFileViewerSelecting([url])
            bringFileViewerForwardIfRefused()
        case .openDirectory:
            guard let finder = applicationURL(for: FileViewerPolicy.finderBundleID) else {
                NSWorkspace.shared.open(url)
                return
            }
            NSWorkspace.shared.open(
                [url], withApplicationAt: finder, configuration: NSWorkspace.OpenConfiguration())
        }
    }

    /// While `.regular` and inactive, cooperative activation refuses the viewer's own activation.
    @MainActor
    private static func bringFileViewerForwardIfRefused() {
        guard NSApp.activationPolicy() == .regular, !NSApp.isActive,
            let viewer = NSWorkspace.shared.urlForApplication(
                withBundleIdentifier: FileViewerPolicy.finderBundleID)
        else { return }
        NSWorkspace.shared.openApplication(at: viewer, configuration: NSWorkspace.OpenConfiguration())
    }

    @MainActor
    private static func applicationURL(for bundleID: String) -> URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
    }

    @MainActor
    private static func bundleName(at url: URL?, bundleID: String) -> String {
        guard let url, let bundle = Bundle(url: url) else { return bundleID }
        return bundle.installedAppName
    }

    private static func normalizedBundleID(_ bundleID: String?) -> String? {
        let trimmed = bundleID?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
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

    @MainActor
    @discardableResult
    static func quit(bundleID: String, url: URL? = nil, force: Bool = false) -> Bool {
        let running = runningApplications(bundleID: bundleID, at: url)
        for app in running {
            if force { app.forceTerminate() } else { app.terminate() }
        }
        return !running.isEmpty
    }

    /// Long enough for any app to exit, short enough not to relaunch under the user.
    private static let exitGrace = Duration.seconds(5)

    /// A refused quit — a save sheet left standing — relaunches nothing.
    @MainActor
    static func restart(bundleID: String, url: URL) async {
        let target = url.resolvingSymlinksInPath().standardizedFileURL
        let running = runningApplications(bundleID: bundleID, at: target)
        guard !running.isEmpty, !Task.isCancelled, await quitAwaitingExit(running), !Task.isCancelled
        else { return }
        launch(target, allowsRunningApplicationSubstitution: false)
    }

    @MainActor
    static func quitAwaitingExit(bundleID: String, url: URL) async -> Bool {
        let running = runningApplications(bundleID: bundleID, at: url)
        return await quitAwaitingExit(running)
    }

    @MainActor
    private static func runningApplications(bundleID: String, at url: URL?) -> [NSRunningApplication] {
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
        guard let target = url?.resolvingSymlinksInPath().standardizedFileURL else { return running }
        return running.filter { $0.bundleURL?.resolvingSymlinksInPath().standardizedFileURL == target }
    }

    @MainActor
    private static func quitAwaitingExit(_ apps: [NSRunningApplication]) async -> Bool {
        guard !Task.isCancelled else { return false }
        for app in apps { app.terminate() }

        let deadline = ContinuousClock.now + exitGrace
        while apps.contains(where: { !$0.isTerminated }) {
            guard !Task.isCancelled, ContinuousClock.now < deadline else { return false }
            do {
                try await Task.sleep(for: .milliseconds(50))
            } catch {
                return false
            }
        }
        return !Task.isCancelled
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
