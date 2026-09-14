import CoreGraphics

/// Pure, with every screen fact injected, so this stays testable off a display.
enum PalettePlacement {
    /// The untouched placement: centred, top edge a fraction of the way down, growing downward.
    static func defaultAnchor(
        in visibleFrame: CGRect, width: CGFloat, topMarginFraction: CGFloat
    )
        -> CGPoint
    {
        CGPoint(
            x: visibleFrame.midX - width / 2,
            y: visibleFrame.maxY - visibleFrame.height * topMarginFraction)
    }

    /// Kept against its display: right of its left edge, down from its top.
    static func offset(of anchor: CGPoint, on visibleFrame: CGRect) -> CGPoint {
        CGPoint(x: anchor.x - visibleFrame.minX, y: visibleFrame.maxY - anchor.y)
    }

    static func anchor(for offset: CGPoint, on visibleFrame: CGRect) -> CGPoint {
        CGPoint(x: visibleFrame.minX + offset.x, y: visibleFrame.maxY - offset.y)
    }

    /// Nil once the display shows too little of the compact bar to grab it back.
    static func restored(
        _ stored: CGPoint, graspable: CGSize, visibleFrame: CGRect, minimumVisible: CGFloat
    ) -> CGPoint? {
        let bar = CGRect(
            x: stored.x, y: stored.y - graspable.height,
            width: graspable.width, height: graspable.height)
        let shown = visibleFrame.intersection(bar)
        return !shown.isNull && shown.width >= minimumVisible && shown.height >= minimumVisible
            ? stored : nil
    }

    /// Near enough to the default placement that releasing the drag should drop it home.
    static func isSnapping(_ anchor: CGPoint, to home: CGPoint, within distance: CGFloat) -> Bool {
        abs(anchor.x - home.x) <= distance && abs(anchor.y - home.y) <= distance
    }
}

/// The three screen-space anchors a menu window can follow.
enum MenuPanelCorner {
    case bottomLeading
    case bottomTrailing
    case belowHeaderTrailing

    var layerAnchor: CGPoint {
        switch self {
        case .bottomLeading: CGPoint(x: 0, y: 0)
        case .bottomTrailing: CGPoint(x: 1, y: 0)
        case .belowHeaderTrailing: CGPoint(x: 1, y: 1)
        }
    }

    func layerPosition(in size: CGSize) -> CGPoint {
        CGPoint(x: size.width * layerAnchor.x, y: size.height * layerAnchor.y)
    }

    func frame(
        contentSize: CGSize, parentFrame: CGRect, inset: CGFloat, headerExtent: CGFloat
    ) -> CGRect {
        let origin: CGPoint =
            switch self {
            case .bottomLeading:
                CGPoint(x: parentFrame.minX + inset, y: parentFrame.minY + inset)
            case .bottomTrailing:
                CGPoint(
                    x: parentFrame.maxX - inset - contentSize.width,
                    y: parentFrame.minY + inset)
            case .belowHeaderTrailing:
                CGPoint(
                    x: parentFrame.maxX - inset * 2 - contentSize.width,
                    y: parentFrame.maxY - headerExtent - contentSize.height)
            }
        return CGRect(origin: origin, size: contentSize)
    }

    func scaledFrame(_ frame: CGRect, by scale: CGFloat) -> CGRect {
        let size = CGSize(width: frame.width * scale, height: frame.height * scale)
        let anchor = layerAnchor
        let origin = CGPoint(
            x: frame.minX - (size.width - frame.width) * anchor.x,
            y: frame.minY - (size.height - frame.height) * anchor.y)
        return CGRect(origin: origin, size: size)
    }
}
