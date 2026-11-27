import SwiftUI

enum BrandArtwork {
    struct Atmosphere: View {
        @Environment(\.colorScheme) private var colorScheme

        var body: some View {
            GeometryReader { geometry in
                ZStack {
                    Theme.Colors.brandCanvas
                    RadialGradient(
                        colors: [Theme.Colors.brand.opacity(colorScheme == .dark ? 0.24 : 0.10), .clear],
                        center: UnitPoint(x: 0.49, y: 0.05),
                        startRadius: 0, endRadius: geometry.size.width * 0.63)
                    Grain()
                        .opacity(colorScheme == .dark ? 0.085 : 0.04)
                        .blendMode(.softLight)
                }
            }
            .accessibilityHidden(true)
        }
    }

    struct Mark: View {
        let height: CGFloat

        static var silhouette: some View {
            Image("MenuBarIcon")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
        }

        var body: some View {
            Self.silhouette
                .foregroundStyle(
                    LinearGradient(
                        colors: [Theme.Colors.brandHighlight, Theme.Colors.brand],
                        startPoint: .topLeading, endPoint: .bottomTrailing)
                )
                .frame(width: height, height: height)
                .shadow(color: Theme.Colors.brand.opacity(0.62), radius: height * 0.22)
                .accessibilityHidden(true)
        }
    }

    struct Grain: View {
        private static let texture: CGImage? = {
            let side = 128
            var seed: UInt32 = 0x71AC57
            let pixels = (0..<(side * side)).map { _ in
                seed = seed &* 1_664_525 &+ 1_013_904_223
                return UInt8(truncatingIfNeeded: seed >> 24)
            }
            guard let provider = CGDataProvider(data: Data(pixels) as CFData) else { return nil }
            return CGImage(
                width: side, height: side, bitsPerComponent: 8, bitsPerPixel: 8,
                bytesPerRow: side, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: [],
                provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
        }()

        var body: some View {
            if let texture = Self.texture {
                Image(decorative: texture, scale: 2)
                    .resizable(resizingMode: .tile)
                    .interpolation(.none)
            }
        }
    }
}
