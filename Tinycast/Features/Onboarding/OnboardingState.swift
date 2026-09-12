import Foundation

/// The first-run marker as a file, not a default: cfprefsd resurrects a deleted default.
enum OnboardingState {
    private static let markerURL = AppPaths.applicationSupport()
        .appendingPathComponent("onboarded")

    static var hasOnboarded: Bool {
        FileManager.default.fileExists(atPath: markerURL.path)
    }

    /// Written at show-time, so onboarding stays one-time even if they quit mid-flow.
    static func markShown() {
        try? Data().write(to: markerURL)
    }
}
