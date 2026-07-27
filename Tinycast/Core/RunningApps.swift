import AppKit

/// Tracks running apps for the launcher's running indicator, updating live from NSWorkspace launch/terminate notifications.
@MainActor
final class RunningAppsMonitor: ObservableObject {
    @Published private(set) var runningBundleIDs: Set<String> = []
    private var observers: [NotificationToken] = []

    init() {
        refresh()
        let center = NSWorkspace.shared.notificationCenter
        for name in [
            NSWorkspace.didLaunchApplicationNotification,
            NSWorkspace.didTerminateApplicationNotification,
        ] {
            let token = center.addObserver(forName: name, object: nil, queue: .main) {
                [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            }
            observers.append(NotificationToken(token, center: center))
        }
    }

    /// True when the entry's bundle is currently running — drives the row's running dot and the Quit action.
    func isRunning(_ app: AppEntry) -> Bool {
        guard let bundleID = app.bundleID else { return false }
        return runningBundleIDs.contains(bundleID)
    }

    /// Launch/terminate fire for helpers and agents the launcher never lists, so republish only on a real change — an unconditional assign would invalidate every observer for nothing.
    private func refresh() {
        let next = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        guard next != runningBundleIDs else { return }
        runningBundleIDs = next
    }
}
