import SwiftUI

extension View {
    func dialogTextField() -> some View {
        modifier(DialogTextField())
    }
}

private struct DialogTextField: ViewModifier {
    @Environment(\.metrics) private var metrics

    func body(content: Content) -> some View {
        content
            .textFieldStyle(.plain)
            .labelsHidden()
            .font(metrics.typography.rowTitle)
            .padding(.horizontal, metrics.spacing.lg)
            .frame(height: metrics.size.dialogButtonHeight)
            .background(
                RoundedRectangle(cornerRadius: metrics.radius.row, style: .continuous)
                    .fill(Theme.Colors.controlSurface))
    }
}
