// Adapted from Rooms (MIT): https://github.com/saragordic/rooms/blob/main/LICENSE
import CoreGraphics
import Foundation

/// One window the sweep found. A handle, not an `AXUIElement`: this layer stays pure.
struct RoomLiveWindow: Equatable, Sendable {
    var handle: Int
    var bundleID: String
    var appName: String
    var title: String
    var windowID: UInt32?
    var frame: CGRect
    var isMinimized = false
    var isAppHidden = false
    /// The window server's front-to-back order; `.max` when it is not on screen.
    var frontRank = Int.max
    var appURL: URL?
}

/// Everything entering a room does on one display, decided before a single AX write. Pure.
struct RoomPlan: Equatable, Sendable {
    struct Placement: Equatable, Sendable {
        var index: Int
        var handle: Int
        var frame: CGRect
    }

    /// Room order, main window first: raised in reverse, it ends frontmost.
    var placements: [Placement]
    var missing: [Int]
    /// Other windows of the room's apps: they park, since hiding them would hide the room too.
    var parks: [Int]
    var keeps: Set<String>

    /// The desktop's own app comes back whenever another hides, so its windows park instead.
    static let parksInsteadOfHiding: Set<String> = ["com.apple.finder"]

    /// Deliberately blind to the feature switch: that guard lives in the coordinator.
    static func make(
        _ room: Room, windows: [RoomLiveWindow], on screen: WindowLayoutScreen, gap: CGFloat,
        minimums: [String: CGSize], claimed: Set<UInt32> = []
    ) -> RoomPlan {
        let assignment = RoomWindowMatcher.assign(room.windows, to: windows, claimed: claimed)
        let found = room.windows.indices.filter { assignment[$0] != nil }
        let frames = frames(
            for: room, indices: found, kind: room.layout(onDisplay: screen.display.uuid),
            in: screen.screen.visibleFrame, gap: gap,
            minimums: found.map { minimums[room.windows[$0].bundleID] ?? .zero })
        let placements = zip(found, frames).compactMap { index, frame -> Placement? in
            assignment[index].map { Placement(index: index, handle: windows[$0].handle, frame: frame) }
        }
        let placed = Set(placements.map(\.handle))
        let roomApps = Set(placements.map { room.windows[$0.index].bundleID })
        let parks = windows.filter {
            !placed.contains($0.handle) && !$0.isMinimized
                && (roomApps.contains($0.bundleID) || parksInsteadOfHiding.contains($0.bundleID))
        }.map(\.handle)
        return RoomPlan(
            placements: placements, missing: room.windows.indices.filter { assignment[$0] == nil },
            parks: parks,
            keeps: Set(room.windows.map(\.bundleID)).union(parksInsteadOfHiding))
    }

    /// Where the windows at `indices` go; a layout that no longer fits falls back to Auto.
    static func frames(
        for room: Room, indices: [Int], kind: RoomLayoutKind, in visible: CGRect, gap: CGFloat,
        minimums: [CGSize]
    ) -> [CGRect] {
        let count = indices.count
        let auto = {
            RoomLayoutEngine.frames(
                count: count, kind: .auto, in: visible, gap: gap, minimums: minimums)
        }
        switch kind {
        case .saved:
            let rects = indices.map { index in
                WindowPlacementEngine.clamped(
                    RoomParking.returnFrame(
                        for: room.windows[index].frame(in: visible), screens: [visible]),
                    into: visible)
            }
            return rects.allSatisfy(visible.contains) ? rects : auto()
        case .custom:
            let cells = indices.compactMap { room.windows[$0].cell }
            guard cells.count == count, count == room.windows.count,
                let rects = RoomGrid.frames(cells, in: visible, gap: gap, minimums: minimums)
            else { return auto() }
            let box = RoomLayoutEngine.Area(visible: visible, gap: gap).canvas
            return RoomLayoutEngine.isClean(rects, in: box.insetBy(dx: -1, dy: -1)) ? rects : auto()
        case .focus, .columns, .grid:
            guard
                RoomLayoutEngine.fits(
                    count: count, kind: kind, in: visible, gap: gap, minimums: minimums)
            else { return auto() }
            return RoomLayoutEngine.frames(
                count: count, kind: kind, in: visible, gap: gap, minimums: minimums)
        case .auto, .stack:
            return RoomLayoutEngine.frames(
                count: count, kind: kind, in: visible, gap: gap, minimums: minimums)
        }
    }

    /// What Tab steps through here: every layout that fits and looks unlike the others.
    static func layoutChoices(
        for room: Room, windows: [RoomLiveWindow], on screen: WindowLayoutScreen, gap: CGFloat,
        minimums: [String: CGSize], claimed: Set<UInt32> = []
    ) -> [RoomLayoutKind] {
        let visible = screen.screen.visibleFrame
        let assignment = RoomWindowMatcher.assign(room.windows, to: windows, claimed: claimed)
        let present = room.windows.indices.filter { assignment[$0] != nil }
        let count = present.count
        let current = room.layout(onDisplay: screen.display.uuid)
        guard count > 1 else { return current == .auto ? [.auto] : [.auto, current] }
        let sizes = present.map { minimums[room.windows[$0].bundleID] ?? .zero }
        let auto = RoomLayoutEngine.frames(
            count: count, kind: .auto, in: visible, gap: gap, minimums: sizes)
        var seen: [[CGRect]] = []
        var choices: [RoomLayoutKind] = []
        for kind in RoomLayoutKind.allCases {
            switch kind {
            case .custom:
                let complete =
                    count == room.windows.count
                    && present.allSatisfy { room.windows[$0].cell != nil }
                if complete,
                    frames(
                        for: room, indices: present, kind: .custom, in: visible, gap: gap,
                        minimums: sizes) != auto
                {
                    choices.append(kind)
                }
            case .saved:
                // Only Remember Arrangement makes one, so Tab never invents it.
                if current == .saved { choices.append(kind) }
            case .auto, .focus, .stack, .columns, .grid:
                guard
                    RoomLayoutEngine.fits(
                        count: count, kind: kind, in: visible, gap: gap, minimums: sizes)
                else { continue }
                let rects = RoomLayoutEngine.frames(
                    count: count, kind: kind, in: visible, gap: gap, minimums: sizes)
                if kind != .auto, seen.contains(rects) { continue }
                seen.append(rects)
                choices.append(kind)
            }
        }
        // Stack's overlapping cards only when nothing tidier fits.
        if current != .stack, choices.contains(where: { [.focus, .columns, .grid].contains($0) }) {
            choices.removeAll { $0 == .stack }
        }
        return choices
    }

    /// The choice after `current`, wrapping; nil when only one layout fits, so Tab can say so.
    static func nextLayout(
        after current: RoomLayoutKind, in choices: [RoomLayoutKind], backwards: Bool
    ) -> RoomLayoutKind? {
        guard choices.count > 1 else { return nil }
        let index = choices.firstIndex(of: current) ?? 0
        return choices[(index + (backwards ? choices.count - 1 : 1)) % choices.count]
    }
}
