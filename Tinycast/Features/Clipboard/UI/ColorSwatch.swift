import SwiftUI

/// The one place a colour is drawn, over the checkerboard that makes its alpha visible.
struct ColorSwatch: View {
    let color: ColorValue
    var cornerRadius: CGFloat = Theme.Radius.thumbnail

    /// A colour is content, not chrome, so it carries the same hairline a thumbnail does.
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        shape
            .fill(Theme.Colors.controlSurface)
            // Built only where there is alpha, else every row pays for a Canvas nothing can see.
            .overlay { if color.hasAlpha { CheckerboardPattern().clipShape(shape) } }
            .overlay { shape.fill(color.swiftUIColor) }
            .overlay { shape.strokeBorder(Theme.Colors.cardStroke, lineWidth: 1) }
            // A swatch renders no text at all, so VoiceOver would otherwise reach nothing.
            .accessibilityElement()
            .accessibilityLabel(ColorFormat.primary(for: color).string(for: color))
    }
}

/// The transparency backdrop: two greys, so a half-alpha colour reads as translucent.
private struct CheckerboardPattern: View {
    private static let cell: CGFloat = 5

    var body: some View {
        Canvas { context, size in
            context.fill(
                Path(CGRect(origin: .zero, size: size)), with: .color(Theme.Colors.checkerLight))
            let columns = Int((size.width / Self.cell).rounded(.up))
            let rows = Int((size.height / Self.cell).rounded(.up))
            for row in 0..<rows {
                for column in 0..<columns where (row + column).isMultiple(of: 2) {
                    context.fill(
                        Path(
                            CGRect(
                                x: CGFloat(column) * Self.cell, y: CGFloat(row) * Self.cell,
                                width: Self.cell, height: Self.cell)),
                        with: .color(Theme.Colors.checkerDark))
                }
            }
        }
        .drawingGroup()
    }
}

extension ColorValue {
    /// sRGB in, sRGB out: the components are already in the space SwiftUI's initialiser expects.
    var swiftUIColor: Color {
        Color(.sRGB, red: red, green: green, blue: blue, opacity: alpha)
    }
}
