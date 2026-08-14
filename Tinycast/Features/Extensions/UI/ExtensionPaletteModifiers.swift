import SwiftUI

/// The two things a running command adds to the palette's own chrome.
///
/// They are modifiers rather than inline branches for two reasons: `RootPaletteView.body` stays inside
/// what the type checker will solve, and — the reason they live here — the palette never has to hold
/// an extension's layout. It attaches these and knows nothing else about them.

/// An extension action can declare its own shortcut, matched against the running command's panel
/// before the palette's own bindings see the keystroke.
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
