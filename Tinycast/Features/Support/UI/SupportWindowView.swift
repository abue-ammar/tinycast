import SwiftUI

struct SupportWindowView: View {
    /// Held directly, not injected: it publishes nothing, so `@Observable` would buy nothing.
    let support: SupportCoordinator

    @Environment(AppSettings.self) private var settings

    static let width: CGFloat = 460
    /// Only until the first layout measures the real one, which is what the window then takes.
    static let initialSize = CGSize(width: width, height: 400)

    private static let markSize: CGFloat = 64
    /// Narrow enough that the English pitch breaks at its comma.
    private static let pitchWidth: CGFloat = 260

    var body: some View {
        @Bindable var settings = settings
        return VStack(spacing: Theme.Spacing.xxxl) {
            BrandArtwork.Mark(height: Self.markSize)
            pitch
            action
            Toggle("Remind me occasionally", isOn: $settings.supportRemindersEnabled)
                .toggleStyle(.checkbox)
                .font(.callout)
                .foregroundStyle(Theme.Colors.textSecondary)
                .help(
                    "About once a month. Turn this off and \(Bundle.main.appDisplayName) asks at most once a year."
                )
        }
        // Less on top: the title bar already contributes its own 32pt above this.
        .padding(.top, Theme.Spacing.md)
        .padding([.horizontal, .bottom], Theme.Spacing.xxxl)
        // The ideal height, not the window's: measuring its own output would feed back.
        .fixedSize(horizontal: false, vertical: true)
        .onGeometryChange(for: CGFloat.self) {
            $0.size.height
        } action: {
            support.fit(height: $0)
        }
        .frame(maxWidth: .infinity, alignment: .top)
        .background { BrandArtwork.Atmosphere().ignoresSafeArea() }
        .tint(Theme.Colors.brand)
    }

    private var pitch: some View {
        VStack(spacing: Theme.Spacing.md) {
            Text("Enjoying \(Bundle.main.appDisplayName)?")
                .font(.largeTitle.weight(.bold))
                .accessibilityAddTraits(.isHeader)
            Text("If it earns a place on your Mac, consider supporting its development.")
                .font(.title3)
                .foregroundStyle(Theme.Colors.textSecondary)
                .frame(maxWidth: Self.pitchWidth)
                .fixedSize(horizontal: false, vertical: true)
        }
        .multilineTextAlignment(.center)
    }

    private var action: some View {
        Button {
            support.openCheckout()
        } label: {
            Label(String(localized: "Support \(Bundle.main.appDisplayName)"), systemImage: "heart.fill")
                .font(.headline)
                .padding(.horizontal, Theme.Spacing.md)
        }
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.capsule)
        .controlSize(.extraLarge)
        .padding(.top, Theme.Spacing.sm)
    }
}
