import CoreGraphics
import Foundation

/// Resolves a layout entry to a frame and back again. Pure, and entirely in AX space.
enum WindowLayoutGeometry {
    /// Matches `WindowPlacementEngine.tile`'s own floor: never write a zero-area frame.
    static let minimumLength: CGFloat = 1

    /// The box an entry's fractions are of. A zero gap makes this the plain visible frame.
    static func box(_ screen: WindowPlacementEngine.Screen, gap: CGFloat) -> CGRect {
        WindowPlacementEngine.canvas(
            screen.visibleFrame,
            gap: WindowPlacementEngine.sanitizedGap(gap, in: screen.visibleFrame))
    }

    /// The frame an entry asks for, or nil when the display has no usable visible frame.
    static func resolve(
        _ entry: WindowLayoutEntry, on screen: WindowPlacementEngine.Screen, gap: CGFloat
    ) -> CGRect? {
        let box = box(screen, gap: gap)
        guard box.width > 0, box.height > 0 else { return nil }

        let size = CGSize(
            width: length(box.width * fraction(entry.widthFraction), in: box.width),
            height: length(box.height * fraction(entry.heightFraction), in: box.height))

        // Offset before the clamp: the nudge is the user's intent, the clamp only a safety net.
        let placed = entry.anchor.placement.place(size, in: box)
            .offsetBy(dx: nudge(entry.offset.x), dy: nudge(entry.offset.y))
        return WindowPlacementEngine.rounded(WindowPlacementEngine.clamped(placed, into: box))
    }

    /// What `resolve` needs to reproduce an observed frame.
    struct Capture: Equatable, Sendable {
        var widthFraction: CGFloat
        var heightFraction: CGFloat
        var anchor: WindowLayoutAnchor
        var offset: CGPoint
    }

    /// The inverse of `resolve`: `resolve(describe(frame)) == frame` for any frame inside the box.
    static func describe(
        _ frame: CGRect, on screen: WindowPlacementEngine.Screen, gap: CGFloat
    ) -> Capture {
        let box = box(screen, gap: gap)
        guard box.width > 0, box.height > 0 else {
            return Capture(widthFraction: 1, heightFraction: 1, anchor: .center, offset: .zero)
        }

        // Clamped before the ratio, so a stored fraction is always one `resolve` can reproduce.
        let size = CGSize(
            width: min(frame.width, box.width), height: min(frame.height, box.height))
        let horizontal = nearestAxis(
            frame.minX, boxMin: box.minX, boxLength: box.width, length: size.width)
        let vertical = nearestAxis(
            frame.minY, boxMin: box.minY, boxLength: box.height, length: size.height)
        let anchor = WindowLayoutAnchor.named(horizontal: horizontal, vertical: vertical)
        let origin = anchor.placement.place(size, in: box).origin

        // The residual stays exact: a centred anchor on an odd free space lands on a half point,
        // and rounding here would move the window by one. `resolve` rounds the composed frame.
        return Capture(
            widthFraction: size.width / box.width, heightFraction: size.height / box.height,
            anchor: anchor,
            offset: CGPoint(x: frame.minX - origin.x, y: frame.minY - origin.y))
    }

    /// The entry a captured window becomes, on the display it was found on.
    static func entry(
        bundleID: String, display: WindowLayoutDisplay, frame: CGRect,
        on screen: WindowPlacementEngine.Screen
    ) -> WindowLayoutEntry {
        // Gapless, so a later change to `windowGap` cannot move every captured window.
        let capture = describe(frame, on: screen, gap: 0)
        return WindowLayoutEntry(
            bundleID: bundleID, display: display, widthFraction: capture.widthFraction,
            heightFraction: capture.heightFraction, anchor: capture.anchor, offset: capture.offset)
    }

    // MARK: - Primitives

    /// `place` derives each axis from its own axis alone, so the nearest of nine is 3 + 3.
    private static func nearestAxis(
        _ position: CGFloat, boxMin: CGFloat, boxLength: CGFloat, length: CGFloat
    ) -> WindowPlacementEngine.Anchor.Axis {
        let free = boxLength - length
        // Centre first, so an exact tie keeps "stay centred" rather than pinning to an edge.
        let candidates: [(WindowPlacementEngine.Anchor.Axis, CGFloat)] = [
            (.center, boxMin + free / 2), (.min, boxMin), (.max, boxMin + free)
        ]
        var best = candidates[0]
        for candidate in candidates.dropFirst()
        where abs(position - candidate.1) < abs(position - best.1) {
            best = candidate
        }
        return best.0
    }

    private static func fraction(_ value: CGFloat) -> CGFloat {
        guard value.isFinite else { return 1 }
        let range = WindowLayoutEntry.fractionRange
        return min(max(value, range.lowerBound), range.upperBound)
    }

    private static func length(_ value: CGFloat, in available: CGFloat) -> CGFloat {
        min(available, max(minimumLength, value))
    }

    private static func nudge(_ value: CGFloat) -> CGFloat { value.isFinite ? value : 0 }
}
