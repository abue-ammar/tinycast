import SwiftUI

extension View {
    /// Extension-owned surface; the Settings shell only hosts it as an opaque box.
    func extensionSettingsEditorPanelSurface() -> some View {
        modifier(ExtensionSettingsEditorPanelSurface())
    }

    func extensionSettingsEditorTextField() -> some View {
        textFieldStyle(.plain)
            .padding(.horizontal, Theme.Spacing.lg)
            .frame(height: Theme.Size.dialogButtonHeight)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
                    .fill(Theme.Colors.controlSurface))
    }
}

private struct ExtensionSettingsEditorPanelSurface: ViewModifier {
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .continuous)
        content
            .background(Theme.Colors.panelScrim, in: shape)
            .glassEffect(.regular, in: shape)
    }
}

struct ExtensionSettingsEditorHeader: View {
    let title: String
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text(title).font(Theme.Typography.panelTitle)
            if let subtitle {
                Text(subtitle)
                    .font(Theme.Typography.rowTitle)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct ExtensionSettingsEditorButtonStyle: ButtonStyle {
    enum Role { case standard, primary, cancel }

    let role: Role
    var fillsWidth = true

    func makeBody(configuration: Configuration) -> some View {
        ExtensionSettingsEditorButtonBody(
            configuration: configuration, role: role, fillsWidth: fillsWidth)
    }
}

private struct ExtensionSettingsEditorButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let role: ExtensionSettingsEditorButtonStyle.Role
    let fillsWidth: Bool

    @Environment(\.isEnabled) private var isEnabled
    @State private var hovered = false

    var body: some View {
        configuration.label
            .font(Theme.Typography.rowTrailing)
            .foregroundStyle(labelColor)
            .padding(.horizontal, Theme.Spacing.xl)
            .frame(maxWidth: fillsWidth ? .infinity : nil)
            .frame(height: Theme.Size.dialogButtonHeight)
            .contentShape(Capsule())
            .background(Capsule().fill(fill))
            .opacity(isEnabled ? 1 : 0.45)
            .onHover { hovered = $0 }
    }

    private var fill: Color {
        switch role {
        case .primary:
            Theme.Colors.primaryAction.opacity(isHighlighted ? 0.28 : 0.20)
        case .standard, .cancel:
            isHighlighted ? Theme.Colors.selection : Theme.Colors.controlSurface
        }
    }

    private var labelColor: Color {
        switch role {
        case .standard: .primary
        case .primary: Theme.Colors.primaryAction
        case .cancel: Theme.Colors.textSecondary
        }
    }

    private var isHighlighted: Bool { hovered || configuration.isPressed }
}
