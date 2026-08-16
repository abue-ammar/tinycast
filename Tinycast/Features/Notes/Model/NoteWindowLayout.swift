import CoreGraphics
import Foundation

enum NoteWindowLayout {
    struct Metrics: Sendable, Equatable {
        let minimumHeight: CGFloat
        let maximumHeight: CGFloat
        let screenMargin: CGFloat
        let fixedContentHeight: CGFloat
    }

    static func panelHeight(
        editorContentHeight: CGFloat,
        visibleScreenHeight: CGFloat,
        metrics: Metrics
    ) -> CGFloat {
        let desired = metrics.fixedContentHeight + max(0, editorContentHeight)
        return clampedPanelHeight(
            desired,
            visibleScreenHeight: visibleScreenHeight,
            metrics: metrics)
    }

    static func preservedPanelHeight(
        _ currentPanelHeight: CGFloat,
        visibleScreenHeight: CGFloat,
        metrics: Metrics
    ) -> CGFloat {
        clampedPanelHeight(
            currentPanelHeight,
            visibleScreenHeight: visibleScreenHeight,
            metrics: metrics)
    }

    static func resizedFrame(
        currentFrame: CGRect,
        height: CGFloat,
        visibleFrame: CGRect,
        width: CGFloat
    ) -> CGRect {
        constrainedFrame(
            CGRect(
                x: currentFrame.minX,
                y: currentFrame.maxY - height,
                width: width,
                height: height),
            to: visibleFrame)
    }

    static func initialFrame(
        visibleFrame: CGRect,
        height: CGFloat,
        width: CGFloat,
        centerLiftFraction: CGFloat
    ) -> CGRect {
        constrainedFrame(
            CGRect(
                x: visibleFrame.midX - width / 2,
                y: visibleFrame.midY + visibleFrame.height * centerLiftFraction - height / 2,
                width: width,
                height: height),
            to: visibleFrame)
    }

    static func constrainedVisibleFrame(_ visibleFrame: CGRect, metrics: Metrics) -> CGRect {
        let margin = max(0, metrics.screenMargin)
        guard visibleFrame.height >= metrics.minimumHeight + margin * 2 else {
            return visibleFrame
        }
        return visibleFrame.insetBy(dx: 0, dy: margin)
    }

    private static func constrainedFrame(_ proposedFrame: CGRect, to visibleFrame: CGRect) -> CGRect {
        var frame = proposedFrame
        frame.size.height = min(max(0, frame.height), max(0, visibleFrame.height))
        if frame.maxX > visibleFrame.maxX { frame.origin.x = visibleFrame.maxX - frame.width }
        if frame.minX < visibleFrame.minX { frame.origin.x = visibleFrame.minX }
        if frame.minY < visibleFrame.minY { frame.origin.y = visibleFrame.minY }
        if frame.maxY > visibleFrame.maxY { frame.origin.y = visibleFrame.maxY - frame.height }
        return frame
    }

    private static func clampedPanelHeight(
        _ proposedHeight: CGFloat,
        visibleScreenHeight: CGFloat,
        metrics: Metrics
    ) -> CGFloat {
        let visibleHeight = max(0, visibleScreenHeight)
        let minimum = min(metrics.minimumHeight, visibleHeight)
        let marginsFit = visibleHeight >= metrics.minimumHeight + metrics.screenMargin * 2
        let availableHeight =
            marginsFit
            ? max(0, visibleHeight - metrics.screenMargin * 2)
            : visibleHeight
        let maximum = min(metrics.maximumHeight, availableHeight)
        return min(
            max(proposedHeight, minimum),
            max(minimum, maximum))
    }
}
