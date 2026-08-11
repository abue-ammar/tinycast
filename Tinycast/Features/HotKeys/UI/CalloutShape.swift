import SwiftUI

/// Rounded rect plus a rounded-tip triangle pointer, as one continuous floating surface.
struct CalloutShape: Shape {
    let caretEdge: CalloutPlacement.CaretEdge
    let caretX: CGFloat
    var cornerRadius: CGFloat = Theme.Radius.menuPanel
    var caretWidth: CGFloat = Theme.Size.calloutCaretWidth
    var caretHeight: CGFloat = Theme.Size.calloutCaretHeight
    var tipRadius: CGFloat = Theme.Size.calloutCaretTip

    func path(in rect: CGRect) -> Path {
        let up = caretEdge == .top
        let body = CGRect(
            x: rect.minX, y: up ? rect.minY + caretHeight : rect.minY,
            width: rect.width, height: rect.height - caretHeight)
        var path = Path(roundedRect: body, cornerRadius: cornerRadius, style: .continuous)

        let half = caretWidth / 2
        let baseY = up ? body.minY : body.maxY
        let tipY = up ? rect.minY : rect.maxY
        // Two straight edges meeting at an arc: a triangle whose tip is rounded, not a dome.
        path.move(to: CGPoint(x: caretX - half, y: baseY))
        path.addArc(
            tangent1End: CGPoint(x: caretX, y: tipY),
            tangent2End: CGPoint(x: caretX + half, y: baseY),
            radius: tipRadius)
        path.addLine(to: CGPoint(x: caretX + half, y: baseY))
        path.closeSubpath()
        return path
    }
}
