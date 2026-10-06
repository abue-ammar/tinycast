import CoreGraphics

enum NoteWindowPlacement {
    /// The top edge holds until the bottom would leave the visible frame, then the window moves up.
    static func fitting(
        _ frame: CGRect, toHeight height: CGFloat, within heights: ClosedRange<CGFloat>,
        in visibleFrame: CGRect
    ) -> CGRect {
        let height = min(heights.upperBound, visibleFrame.height, max(heights.lowerBound, ceil(height)))
        return CGRect(
            x: frame.minX,
            y: max(visibleFrame.minY, min(frame.maxY, visibleFrame.maxY) - height),
            width: frame.width,
            height: height)
    }

    static func topRight(_ frame: CGRect, in visibleFrame: CGRect, inset: CGFloat) -> CGRect {
        let horizontalInset = min(inset, max(0, visibleFrame.width - frame.width))
        let verticalInset = min(inset, max(0, visibleFrame.height - frame.height))
        return CGRect(
            x: visibleFrame.maxX - frame.width - horizontalInset,
            y: visibleFrame.maxY - frame.height - verticalInset,
            width: frame.width,
            height: frame.height)
    }
}
