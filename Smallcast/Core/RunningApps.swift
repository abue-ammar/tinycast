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

    private func refresh() {
        runningBundleIDs = Set(
            NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
    }
}
