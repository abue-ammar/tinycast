import SwiftUI

/// Alignment guides marking the palette's default placement while a drag is in flight.
struct PaletteDropGuideView: View {
    /// The default placement's top-left, in the guide window's flipped coordinates.
    let topLeft: CGPoint
    let width: CGFloat
    /// True once releasing would snap the panel home.
    let armed: Bool

    var body: some View {
        DropGuidePath(topLeft: topLeft, width: width)
            .stroke(
                armed ? Theme.Colors.dropGuideArmed : Theme.Colors.dropGuide,
                style: StrokeStyle(
                    lineWidth: Theme.Size.dropGuideWidth,
                    dash: [Theme.Size.dropGuideDash, Theme.Size.dropGuideDash])
            )
            .animation(.easeInOut(duration: Theme.Duration.tooltip), value: armed)
    }
}

/// Both panel edges run the full height, its top edge the full width — one path, one stroke.
private struct DropGuidePath: Shape {
    let topLeft: CGPoint
    let width: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        for x in [topLeft.x, topLeft.x + width] {
            path.move(to: CGPoint(x: x, y: rect.minY))
            path.addLine(to: CGPoint(x: x, y: rect.maxY))
        }
        path.move(to: CGPoint(x: rect.minX, y: topLeft.y))
        path.addLine(to: CGPoint(x: rect.maxX, y: topLeft.y))
        return path
    }
}
