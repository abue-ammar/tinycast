import SwiftUI

struct IconTile: View {
    @Environment(\.colorScheme) private var colorScheme
    let symbol: String
    let tint: IconTint
    /// The share of the frame the tile paints, so it can sit among app icons' built-in margin.
    var extent: CGFloat = 1

    var body: some View {
        let paint = Paint(tint, IconCache.style.tileTheme, onDarkSurface: colorScheme == .dark)
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height) * extent
            let shape = RoundedRectangle(
                cornerRadius: side * IconCache.appIconCornerRatio, style: .continuous)
            glyph
                .resizable()
                .scaledToFit()
                .fontWeight(.semibold)
                .fontDesign(.rounded)
                .foregroundStyle(paint.ink)
                .frame(width: side * Theme.IconTile.glyphRatio, height: side * Theme.IconTile.glyphRatio)
                .frame(width: side, height: side)
                .background(paint.ground, in: shape)
                .overlay {
                    shape.strokeBorder(
                        Theme.IconTile.edgeLight, lineWidth: side * Theme.IconTile.edgeLightRatio)
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
        }
        // Pin the symbol variant independently of the tile's paint.
        .environment(\.colorScheme, .light)
    }

    private var glyph: Image {
        NSImage(systemSymbolName: symbol, accessibilityDescription: nil) == nil
            ? Image(symbol).renderingMode(.template)
            : Image(systemName: symbol)
    }

    private struct Paint {
        let ground: LinearGradient
        let ink: LinearGradient

        init(_ tint: IconTint, _ theme: SystemIconTheme, onDarkSurface: Bool) {
            let tile = Theme.IconTile.self
            switch (theme.material, theme.isDark(onDarkSurface: onDarkSurface)) {
            case (.regular, false): (ground, ink) = (tile.fill(tint), tile.whiteInk)
            case (.regular, true): (ground, ink) = (tile.darkGround, tile.darkInk(tint))
            case (.clear, false): (ground, ink) = (tile.clearLightGround, tile.clearLightInk)
            case (.clear, true): (ground, ink) = (tile.clearDarkGround, tile.clearDarkInk)
            case (.tinted, false): (ground, ink) = (tile.tinted(theme.tint, isDark: false), tile.whiteInk)
            case (.tinted, true): (ground, ink) = (tile.darkGround, tile.tinted(theme.tint, isDark: true))
            }
        }
    }
}
