import Foundation

/// First-run marker stored as a file in Application Support (not UserDefaults) so a full uninstall — including leftover/`--zap` cleanup — clears it and a reinstall re-runs onboarding; a UserDefaults flag gets resurrected by cfprefsd and survives removal.
enum OnboardingState {
    private static let markerURL: URL = {
        let bundleID = Bundle.main.bundleIdentifier ?? "com.smallcast.app"
        return FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(bundleID, isDirectory: true)
            .appendingPathComponent("onboarded")
    }()

    /// True once onboarding has been shown.
    static var hasOnboarded: Bool {
        FileManager.default.fileExists(atPath: markerURL.path)
    }

    /// Records that onboarding has been shown; called at show-time so it stays one-time even if the user quits mid-flow.
    static func markShown() {
        let dir = markerURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? Data().write(to: markerURL)
    }
}
