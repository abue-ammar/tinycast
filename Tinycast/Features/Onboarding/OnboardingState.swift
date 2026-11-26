import Foundation

/// The first-run marker as a file, not a default: cfprefsd resurrects a deleted default.
enum OnboardingState {
    private static let markerURL = AppPaths.applicationSupport()
        .appendingPathComponent("onboarded")

    static var hasOnboarded: Bool {
        FileManager.default.fileExists(atPath: markerURL.path)
    }

    /// Written when the wizard closes, so quitting partway shows it again from the start.
    static func markOnboarded() {
        try? Data().write(to: markerURL)
    }
}
