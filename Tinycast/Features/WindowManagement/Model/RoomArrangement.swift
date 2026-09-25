// Adapted from Rooms (MIT): https://github.com/saragordic/rooms/blob/main/LICENSE
import CoreGraphics
import Foundation

/// Reads an arrangement made by hand: the layout it is closest to, and who sits where.
enum RoomArrangement {
    struct Reading: Equatable, Sendable {
        var kind: RoomLayoutKind
        /// Window indices in room order for that layout, the main window first.
        var order: [Int]
        /// The furthest any window sits from its spot, averaged over its four edges.
        var distance: CGFloat
        /// Each window's cell, in `order`, when the reading is `.custom`.
        var cells: [RoomGrid.Cell]?
    }

    /// Every window within this many points of its spot reads as that layout.
    static let tolerance: CGFloat = 40

    static func read(
        _ frames: [CGRect], in visible: CGRect, gap: CGFloat, minimums: [CGSize] = []
    ) -> Reading {
        let count = frames.count
        guard count > 1 else {
            return Reading(kind: count == 1 ? .focus : .saved, order: Array(0..<count), distance: 0)
        }
        var best = Reading(kind: .saved, order: Array(0..<count), distance: .infinity)
        for kind in [RoomLayoutKind.focus, .stack, .columns, .grid] {
            let spots = RoomLayoutEngine.frames(
                count: count, kind: kind, in: visible, gap: gap, minimums: minimums)
            var used = Set<Int>()
            var order: [Int] = []
            var worst: CGFloat = 0
            for spot in spots {
                guard
                    let nearest = frames.indices.filter({ !used.contains($0) }).min(by: {
                        distance(frames[$0], spot) < distance(frames[$1], spot)
                    })
                else { break }
                used.insert(nearest)
                order.append(nearest)
                worst = max(worst, distance(frames[nearest], spot))
            }
            // Every window must fit, or three neat thirds would hide a ⅔ + ⅓ row beneath.
            if worst < best.distance { best = Reading(kind: kind, order: order, distance: worst) }
        }
        if best.distance <= tolerance { return best }
        if let cells = RoomGrid.cells(for: frames, in: visible, gap: gap) {
            return Reading(
                kind: .custom, order: Array(0..<count), distance: best.distance, cells: cells)
        }
        return Reading(kind: .saved, order: Array(0..<count), distance: best.distance)
    }

    /// `room` rebuilt from open windows; `keepsOrder` trusts their order over their places.
    static func learn(
        _ room: Room, from windows: [RoomLiveWindow], on screen: WindowLayoutScreen,
        spansDisplays: Bool, gap: CGFloat, minimums: [CGSize], keepsOrder: Bool
    ) -> (room: Room, reading: Reading) {
        let visible = screen.screen.visibleFrame
        var reading = read(windows.map(\.frame), in: visible, gap: gap, minimums: minimums)
        // Windows from several displays have no arrangement to read; the room lands on one.
        if spansDisplays || (keepsOrder && reading.kind == .saved) {
            reading = Reading(
                kind: .auto, order: Array(windows.indices), distance: reading.distance)
        }
        let ordered = keepsOrder ? windows : reading.order.map { windows[$0] }
        var learned = ordered.map { window in
            RoomWindow(
                bundleID: window.bundleID, appName: window.appName, title: window.title,
                windowID: window.windowID,
                unitFrame: RoomWindow.unitFrame(of: window.frame, in: visible))
        }
        if reading.kind == .custom, let cells = reading.cells, cells.count == learned.count {
            for index in learned.indices { learned[index].cell = cells[index] }
        }
        // Remembering keeps the room's closed windows; the picker replaces the whole set.
        let kept =
            keepsOrder
            ? []
            : room.windows.filter { saved in
                !windows.contains { $0.windowID != nil && $0.windowID == saved.windowID }
            }
        var updated = room
        updated.windows = learned + kept
        updated.layoutsByDisplay[screen.display.uuid.lowercased()] = reading.kind
        return (updated, reading)
    }

    private static func distance(_ lhs: CGRect, _ rhs: CGRect) -> CGFloat {
        (abs(lhs.minX - rhs.minX) + abs(lhs.minY - rhs.minY) + abs(lhs.maxX - rhs.maxX)
            + abs(lhs.maxY - rhs.maxY)) / 4
    }
}
