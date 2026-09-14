import SwiftUI

private struct ArmedHover: ViewModifier {
    @Environment(PaletteState.self) private var palette
    @Binding var hovered: Bool

    func body(content: Content) -> some View {
        content
            .onContinuousHover(coordinateSpace: .local) { phase in
                switch phase {
                case .active: hovered = palette.hoverHighlightArmed
                case .ended: hovered = false
                }
            }
            // Disarming under a still pointer fires no hover phase, so the drop clears the row.
            .onChange(of: palette.hoverDisarmToken) { hovered = false }
    }
}

extension View {
    /// Row hover, lit only while the pointer moves; independent of the keyboard selection.
    func armedHover(_ hovered: Binding<Bool>) -> some View {
        modifier(ArmedHover(hovered: hovered))
    }
}
