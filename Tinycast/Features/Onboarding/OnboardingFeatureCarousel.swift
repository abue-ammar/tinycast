import SwiftUI

struct OnboardingFeatureCarousel: View {
    let animates: Bool

    private static let symbols =
        (SettingsSection.features.tabs + SettingsSection.launcher.tabs).map(\.systemImage)
        + [
            CommandID.calculatorHistory.sfSymbol, CommandID.openCamera.sfSymbol,
            CommandID.define.sfSymbol, "keyboard", SettingsTab.backup.systemImage
        ]

    var body: some View {
        let middle = Self.symbols.count / 2
        VStack(spacing: Theme.Spacing.sm) {
            row(Self.symbols[..<middle], speed: Theme.Onboarding.carouselSpeed, reversed: false)
            row(Self.symbols[middle...], speed: Theme.Onboarding.carouselSpeed * 0.85, reversed: true)
        }
        .frame(maxWidth: Theme.Onboarding.carouselWidth)
        .mask {
            LinearGradient(gradient: Theme.Onboarding.carouselFade, startPoint: .leading, endPoint: .trailing)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func row(_ symbols: ArraySlice<String>, speed: CGFloat, reversed: Bool) -> some View {
        let step = Theme.Onboarding.featureIconSize + Theme.Spacing.md
        let loopWidth = step * CGFloat(symbols.count)
        let stagger = reversed ? step / 2 : 0
        let strip = HStack(spacing: Theme.Spacing.md) {
            ForEach(0...(symbols.count * 2), id: \.self) { index in
                tile(symbols[symbols.startIndex + index % symbols.count])
            }
        }
        .fixedSize()
        .offset(x: -stagger)

        return Color.clear.frame(height: Theme.Onboarding.featureIconSize)
            .overlay(alignment: .leading) {
                if animates {
                    strip.keyframeAnimator(initialValue: CGFloat.zero, repeating: true) { content, distance in
                        content.offset(x: reversed ? distance - loopWidth : -distance)
                    } keyframes: { _ in
                        LinearKeyframe(loopWidth, duration: TimeInterval(loopWidth / speed))
                    }
                } else {
                    strip
                }
            }
    }

    private func tile(_ symbol: String) -> some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.formField)
        return Image(systemName: symbol)
            .font(.system(size: Theme.Onboarding.featureSymbolSize, weight: .medium))
            .foregroundStyle(Theme.Colors.brand)
            .frame(width: Theme.Onboarding.featureIconSize, height: Theme.Onboarding.featureIconSize)
            .background {
                shape.fill(Theme.Onboarding.featureIconFill)
                    .overlay {
                        shape.strokeBorder(
                            Theme.Onboarding.featureIconTopEdge, lineWidth: Theme.Size.hairline)
                        shape.strokeBorder(
                            Theme.Onboarding.featureIconBottomEdge, lineWidth: Theme.Size.hairline)
                    }
                    .padding(Theme.Spacing.xxs)
            }
    }
}
