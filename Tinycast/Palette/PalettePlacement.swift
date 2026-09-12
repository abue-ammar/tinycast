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

    /// Nil once no display shows enough of the compact bar to grab it back.
    static func restored(
        _ stored: CGPoint, graspable: CGSize, visibleFrames: [CGRect], minimumVisible: CGFloat
    ) -> CGPoint? {
        let bar = CGRect(
            x: stored.x, y: stored.y - graspable.height,
            width: graspable.width, height: graspable.height)
        let reachable = visibleFrames.contains { screen in
            let shown = screen.intersection(bar)
            return !shown.isNull && shown.width >= minimumVisible && shown.height >= minimumVisible
        }
        return reachable ? stored : nil
    }

    /// Near enough to the default placement that releasing the drag should drop it home.
    static func isSnapping(_ anchor: CGPoint, to home: CGPoint, within distance: CGFloat) -> Bool {
        abs(anchor.x - home.x) <= distance && abs(anchor.y - home.y) <= distance
    }
}
