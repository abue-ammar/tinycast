import SwiftUI

struct IconTile: View {
    let symbol: String
    let tint: IconTint
    /// The share of the frame the tile paints, so it can sit among app icons' built-in margin.
    var extent: CGFloat = 1

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height) * extent
            let shape = RoundedRectangle(
                cornerRadius: side * IconCache.appIconCornerRatio, style: .continuous)
            glyph
                .resizable()
                .scaledToFit()
                .fontWeight(.semibold)
                .fontDesign(.rounded)
                .foregroundStyle(.white)
                .frame(width: side * Theme.IconTile.glyphRatio, height: side * Theme.IconTile.glyphRatio)
                .frame(width: side, height: side)
                .background(Theme.IconTile.fill(tint), in: shape)
                .overlay {
                    shape.strokeBorder(
                        Theme.IconTile.edgeLight, lineWidth: side * Theme.IconTile.edgeLightRatio)
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
        }
        // The tile never changes with appearance, so neither may a glyph that swaps in Dark.
        .environment(\.colorScheme, .light)
    }

    private var glyph: Image {
        NSImage(systemSymbolName: symbol, accessibilityDescription: nil) == nil
            ? Image(symbol).renderingMode(.template)
            : Image(systemName: symbol)
    }
}
