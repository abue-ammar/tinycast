import SwiftUI

/// The first-run wizard's own window lifecycle.
@MainActor
final class OnboardingCoordinator {
    private let window: AppWindowController
    /// Environment injection only — never for state this type owns.
    private unowned let core: AppCore

    init(core: AppCore) {
        self.core = core
        window = AppWindowController(
            title: String(localized: "Welcome to Tinycast", bundle: .appLanguage), contentSize: OnboardingView.windowSize,
            activation: core.activationPolicy)
    }

    func showOnboarding() {
        window.show {
            OnboardingView()
                .environment(self.core)
                .environment(self.core.settings)
                .environment(self.core.hotKeys)
        }
    }

    /// Final step: close the wizard and drop straight into the launcher.
    func finishOnboarding() {
        window.close()
        core.paletteCoordinator.showPalette(mode: .launcher)
    }

    func focusExisting() -> Bool {
        window.focus()
    }
}
