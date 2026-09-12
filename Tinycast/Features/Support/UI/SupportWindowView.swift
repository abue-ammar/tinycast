import AppKit
import SwiftUI

/// The support surface: the ask, the one button, and the reminder switch.
struct SupportWindowView: View {
    /// Held directly, not injected: it publishes nothing, so `@Observable` would buy nothing.
    let support: SupportCoordinator

    @Environment(AppSettings.self) private var settings

    static let width: CGFloat = 460
    /// Only until the first layout measures the real one, which is what the window then takes.
    static let initialSize = CGSize(width: width, height: 340)

    private static let iconSize: CGFloat = 76

    var body: some View {
        @Bindable var settings = settings
        return VStack(spacing: Theme.Spacing.xxl) {
            hero
            action
            reminder(isOn: $settings.supportRemindersEnabled)
        }
        // Less on top: the title bar already contributes its own 32pt above this.
        .padding(.top, Theme.Spacing.md)
        .padding([.horizontal, .bottom], Theme.Spacing.xxl)
        // The ideal height, not the window's: measuring its own output would feed back.
        .fixedSize(horizontal: false, vertical: true)
        .onGeometryChange(for: CGFloat.self) {
            $0.size.height
        } action: {
            support.fit(height: $0)
        }
        .frame(maxWidth: .infinity, alignment: .top)
        // Only the gradient reaches under the titlebar; the content stays in the safe area.
        .background(
            LinearGradient(
                colors: [Theme.Colors.sheen, Color.clear], startPoint: .top, endPoint: .center
            )
            .ignoresSafeArea()
        )
    }

    // MARK: - Hero

    private var hero: some View {
        VStack(spacing: Theme.Spacing.xl) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .frame(width: Self.iconSize, height: Self.iconSize)
                .shadow(color: .black.opacity(0.35), radius: 12, y: 6)
            VStack(spacing: Theme.Spacing.sm) {
                Text("Support \(Bundle.main.appDisplayName)")
                    .font(.title2.weight(.semibold))
                Text("Built with love.")
                    .font(.callout)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Action

    private var action: some View {
        VStack(spacing: Theme.Spacing.lg) {
            SupportActionButton(title: "Support \(Bundle.main.appDisplayName)", icon: "heart") {
                support.openCheckout()
            }
            Text("Secure checkout on Polar.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - Reminder

    private func reminder(isOn: Binding<Bool>) -> some View {
        Toggle("Remind me occasionally", isOn: isOn)
            .toggleStyle(.checkbox)
            .font(.callout)
            .foregroundStyle(Theme.Colors.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .help(
                "About once a month. Turn this off and"
                    + " \(Bundle.main.appDisplayName) won't ask again.")
    }
}

/// The window's one call to action. Local to Support, like every other view this feature owns.
private struct SupportActionButton: View {
    let title: String
    let icon: String
    let action: () -> Void

    @State private var hovered = false

    private static let height: CGFloat = 46

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: icon)
                    .font(.body.weight(.semibold))
                Text(title)
                    .font(.headline)
            }
            // White ink in both appearances: a saturated fill carries its own contrast.
            .foregroundStyle(Color.white)
            .padding(.horizontal, Theme.Spacing.xxxl)
            .frame(height: Self.height)
            .background(
                Capsule()
                    .fill(Theme.Colors.brand)
                    .brightness(hovered ? 0.08 : 0)
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .animation(.easeOut(duration: Theme.Duration.tooltip), value: hovered)
    }
}
