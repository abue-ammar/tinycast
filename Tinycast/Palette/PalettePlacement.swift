import CoreGraphics

/// Pure, with every screen fact injected, so this stays testable off a display.
enum PalettePlacement {
    static let maxSnapEntrySpeedPointsPerSecond: CGFloat = 600

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

    static func expandedCenterY(in visibleFrame: CGRect, expandedHeight: CGFloat) -> CGFloat {
        visibleFrame.midY + expandedHeight / 2
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

    enum HeightSnap: Equatable {
        case home
        case expandedCenter
    }

    struct Snap {
        let anchor: CGPoint
        let centeredX: Bool
        let height: HeightSnap?
    }

    /// Height detents exist only on the invisible vertical centre line.
    static func snapped(
        _ anchor: CGPoint, home: CGPoint, visibleFrame: CGRect,
        expandedHeight: CGFloat, within distance: CGFloat, previous: Snap?, speed: CGFloat
    ) -> Snap {
        let wasCentered = previous?.centeredX ?? false
        let allowsEntry = speed <= maxSnapEntrySpeedPointsPerSecond
        guard abs(anchor.x - home.x) <= distance * (wasCentered ? 2 : 1),
            wasCentered || allowsEntry
        else {
            return Snap(anchor: anchor, centeredX: false, height: nil)
        }
        let expandedY = expandedCenterY(in: visibleFrame, expandedHeight: expandedHeight)
        let candidateHeight: HeightSnap?
        if abs(anchor.y - home.y) <= distance
            && abs(anchor.y - home.y) <= abs(anchor.y - expandedY)
        {
            candidateHeight = .home
        } else if abs(anchor.y - expandedY) <= distance {
            candidateHeight = .expandedCenter
        } else {
            candidateHeight = nil
        }
        let height = allowsEntry || candidateHeight == previous?.height ? candidateHeight : nil
        let y: CGFloat =
            switch height {
            case .home: home.y
            case .expandedCenter: expandedY
            case nil: anchor.y
            }
        return Snap(anchor: CGPoint(x: home.x, y: y), centeredX: true, height: height)
    }
}

enum MenuPanelCorner {
    case bottomLeading
    case bottomTrailing
    case belowHeaderTrailing
    case belowHeaderLeading

    var layerAnchor: CGPoint {
        switch self {
        case .bottomLeading: CGPoint(x: 0, y: 0)
        case .bottomTrailing: CGPoint(x: 1, y: 0)
        case .belowHeaderTrailing: CGPoint(x: 1, y: 1)
        case .belowHeaderLeading: CGPoint(x: 0, y: 1)
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
            case .belowHeaderLeading:
                CGPoint(
                    x: parentFrame.minX + inset * 2,
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
