import SwiftUI

/// An action's own shortcut, matched before the palette's bindings see it.
struct ExtensionShortcutKeys: ViewModifier {
    let screen: ExtensionCommandScreen?
    let selection: Int

    func body(content: Content) -> some View {
        content.onKeyPress(phases: .down) { press in
            guard let screen, !press.modifiers.isEmpty else { return .ignored }
            return screen.dispatchShortcut(
                key: ASCIIKeyboardLayout.keyEquivalent(fallingBackTo: press.key),
                modifiers: press.modifiers,
                at: selection) ? .handled : .ignored
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

struct ExtensionFormKeys: ViewModifier {
    let field: ExtensionFormField
    let onActivate: () -> Void
    let onSubmit: () -> Void
    @Environment(PaletteState.self) private var palette

    func body(content: Content) -> some View {
        content.onKeyPress(keys: ExtensionFormKey.enterKeys.union([.space]), phases: [.down, .repeat]) { press in
            switch ExtensionFormKey.resolve(
                field: field, key: press.key, modifiers: press.modifiers,
                repeating: press.phase == .repeat, menuOpen: palette.menuOpen,
                composing: palette.isComposing)
            {
            case .activate: onActivate()
            case .submit: onSubmit()
            case .consume: break
            case .ignored: return .ignored
            }
            return .handled
        }
    }
}
