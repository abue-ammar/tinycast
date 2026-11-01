import SwiftUI

/// Copy Deeplink on a shortcut field. Only Settings sets it, so onboarding's field offers nothing.
struct ShortcutDeepLink: Sendable {
    let url: @MainActor @Sendable (HotKeyAction) -> URL?
    let copy: @MainActor @Sendable (URL) -> Void
}

extension EnvironmentValues {
    @Entry var shortcutDeepLink: ShortcutDeepLink?
}
