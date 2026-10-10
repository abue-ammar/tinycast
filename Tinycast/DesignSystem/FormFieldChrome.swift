import SwiftUI

struct FormFieldChrome: ViewModifier {
    let focused: Bool
    @Environment(\.metrics) private var metrics

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: metrics.radius.formField, style: .continuous)
        content
            .background(Theme.Colors.cardFill, in: shape)
            .overlay {
                shape.strokeBorder(
                    Theme.Colors.border,
                    lineWidth: focused ? metrics.size.formFieldFocusStroke : Theme.Size.hairline
                )
                .allowsHitTesting(false)
            }
    }
}

extension View {
    func formFieldChrome(focused: Bool) -> some View {
        modifier(FormFieldChrome(focused: focused))
    }
}
