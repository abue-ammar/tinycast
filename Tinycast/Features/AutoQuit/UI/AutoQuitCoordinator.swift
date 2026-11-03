import AppKit

/// The action-panel side of Auto Quit. The settings pane writes `AppSettings` itself.
@MainActor
final class AutoQuitCoordinator {
    private let settings: AppSettings
    private let monitor: AutoQuitMonitor

    init(settings: AppSettings) {
        self.settings = settings
        monitor = AutoQuitMonitor(settings: settings)
    }

    func start() { monitor.start() }

    func applySettings() { monitor.sync() }

    func canConfigure(_ bundleID: String) -> Bool {
        !AutoQuitSchedule.isExcluded(bundleID, ownBundleID: Bundle.main.bundleIdentifier ?? "")
    }

    func isEnabled(_ bundleID: String) -> Bool {
        settings.autoQuitRules.contains { $0.bundleID == bundleID }
    }

    func setEnabled(_ enabled: Bool, bundleID: String) {
        guard canConfigure(bundleID) else { return }
        var rules = settings.autoQuitRules
        if enabled {
            guard !rules.contains(where: { $0.bundleID == bundleID }) else { return }
            rules.append(AutoQuitRule(bundleID: bundleID, minutes: nil))
        } else {
            rules.removeAll { $0.bundleID == bundleID }
        }
        settings.autoQuitRules = rules
    }
}
