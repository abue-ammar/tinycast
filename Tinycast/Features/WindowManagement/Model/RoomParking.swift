// Adapted from Rooms (MIT): https://github.com/saragordic/rooms/blob/main/LICENSE
import CoreGraphics

/// Where a window waits while its room is elsewhere, and where it comes back to.
enum RoomParking {
    /// A 1-pt sliver stays on `visible`, so macOS keeps it; no corner may spill onto a display.
    static func origin(for size: CGSize, on visible: CGRect, avoiding others: [CGRect]) -> CGPoint {
        let corners = [
            CGPoint(x: visible.maxX - 1, y: visible.maxY - 1),
            CGPoint(x: visible.minX + 1 - size.width, y: visible.maxY - 1),
            CGPoint(x: visible.maxX - 1, y: visible.minY + 1 - size.height),
            CGPoint(x: visible.minX + 1 - size.width, y: visible.minY + 1 - size.height)
        ]
        func spill(_ origin: CGPoint) -> CGFloat {
            let parked = CGRect(origin: origin, size: size)
            return others.reduce(0) { $0 + overlapArea($1, parked) }
        }
        return corners.first { spill($0) == 0 }
            ?? corners.min { spill($0) < spill($1) } ?? corners[0]
    }

    /// A way back on a connected display: one whose display is gone comes to the first, fitted.
    static func returnFrame(for frame: CGRect, screens: [CGRect]) -> CGRect {
        guard let first = screens.first, !screens.contains(where: { overlapArea($0, frame) > 0 })
        else { return frame }
        let size = CGSize(width: min(frame.width, first.width), height: min(frame.height, first.height))
        return WindowPlacementEngine.rounded(
            CGRect(
                x: first.midX - size.width / 2, y: first.midY - size.height / 2,
                width: size.width, height: size.height))
    }

    private static func overlapArea(_ lhs: CGRect, _ rhs: CGRect) -> CGFloat {
        let shared = lhs.intersection(rhs)
        return shared.isNull ? 0 : shared.width * shared.height
    }
}
