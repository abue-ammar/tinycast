import SwiftUI

/// An action's own shortcut, matched against the running panel before the palette's bindings see it.
struct ExtensionShortcutKeys: ViewModifier {
    let screen: ExtensionCommandScreen?
    let selection: Int

    func body(content: Content) -> some View {
        content.onKeyPress(phases: .down) { press in
            guard let screen, !press.modifiers.isEmpty else { return .ignored }
            return screen.dispatchShortcut(
                key: press.key, modifiers: press.modifiers, at: selection) ? .handled : .ignored
        }
    }
}

/// Toasts a running view command raised, stacked above the footer.
struct ExtensionToastOverlay: ViewModifier {
    let extensions: ExtensionManager
    let showing: Bool

    func body(content: Content) -> some View {
        content.overlay(alignment: .bottom) {
            if showing, !extensions.toasts.isEmpty {
                ExtensionFeedbackOverlay(
                    toasts: extensions.toasts,
                    onToastAction: { extensions.runToastAction(token: $0) })
            }
        }
    }
}
