import CoreGraphics
import Foundation

enum NoteWindowLayout {
    struct Metrics: Sendable, Equatable {
        let width: CGFloat
        let minimumHeight: CGFloat
        let maximumHeight: CGFloat
        let maximumScreenFraction: CGFloat
        let fixedContentHeight: CGFloat
    }

    static func panelHeight(
        editorContentHeight: CGFloat,
        visibleScreenHeight: CGFloat,
        metrics: Metrics
    ) -> CGFloat {
        let maximum = min(
            metrics.maximumHeight,
            visibleScreenHeight * metrics.maximumScreenFraction)
        let desired = metrics.fixedContentHeight + max(0, editorContentHeight)
        return min(max(desired, metrics.minimumHeight), max(metrics.minimumHeight, maximum))
    }

    static func resizedFrame(
        currentFrame: CGRect,
        height: CGFloat,
        visibleFrame: CGRect,
        width: CGFloat
    ) -> CGRect {
        var frame = CGRect(
            x: currentFrame.minX,
            y: currentFrame.maxY - height,
            width: width,
            height: height)
        if frame.maxX > visibleFrame.maxX { frame.origin.x = visibleFrame.maxX - frame.width }
        if frame.minX < visibleFrame.minX { frame.origin.x = visibleFrame.minX }
        if frame.minY < visibleFrame.minY { frame.origin.y = visibleFrame.minY }
        if frame.maxY > visibleFrame.maxY { frame.origin.y = visibleFrame.maxY - frame.height }
        return frame
    }
}
