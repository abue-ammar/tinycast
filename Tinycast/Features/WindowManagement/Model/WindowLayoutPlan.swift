import CoreGraphics
import Foundation

/// A connected display: the identity an entry matches on, plus its live AX-space geometry.
struct WindowLayoutScreen: Equatable, Sendable {
    var display: WindowLayoutDisplay
    var screen: WindowPlacementEngine.Screen
}

/// One window the inventory found. A handle, not an `AXUIElement`: this layer stays pure.
struct WindowLayoutWindow: Equatable, Sendable {
    var handle: Int
    var bundleID: String
    var frame: CGRect
    /// Only ever used to make the binding order deterministic.
    var title: String

    init(handle: Int, bundleID: String, frame: CGRect, title: String = "") {
        self.handle = handle
        self.bundleID = bundleID
        self.frame = frame
        self.title = title
    }
}

/// Everything running a layout will do, decided before a single AX write. Pure.
struct WindowLayoutPlan: Equatable, Sendable {
    /// Why an entry produced no placement. Each is expected behaviour, not an error.
    enum Skip: Equatable, Sendable {
        case displayDisconnected(name: String)
        /// The display reported no usable visible frame, so `resolve` refused.
        case unresolvableGeometry
        /// An earlier entry already claims this app and argument; there is no window left to give.
        case duplicateTarget
    }

    /// Where the window for a placement comes from.
    enum Source: Equatable, Sendable {
        case existing(handle: Int)
        /// Open it, then take the window that appears.
        case launch
    }

    struct Placement: Equatable, Sendable {
        var entryID: UUID
        var bundleID: String
        var argument: String?
        var source: Source
        var frame: CGRect
        var screenID: Int
        var anchor: WindowLayoutAnchor
        /// The box to re-clamp into when an app refuses to shrink to `frame`.
        var canvas: CGRect
    }

    struct Skipped: Equatable, Sendable {
        var entryID: UUID
        var reason: Skip
    }

    /// In entry order, so a layout with two windows of one app always lands the same way.
    var placements: [Placement]
    var skipped: [Skipped]

    /// One open per launching placement; the plan already guarantees they are distinct.
    var opens: [Placement] { placements.filter { $0.source == .launch } }

    /// The HUD's second clause, derived here so the coordinator stays declarative.
    var skippedSummary: String? {
        guard !skipped.isEmpty else { return nil }
        let displays = Set(
            skipped.compactMap { skip -> String? in
                guard case .displayDisconnected(let name) = skip.reason else { return nil }
                return name
            })
        if !displays.isEmpty, displays.count == skipped.count {
            return displays.count == 1
                ? "1 display not connected" : "\(displays.count) displays not connected"
        }
        return skipped.count == 1 ? "1 entry skipped" : "\(skipped.count) entries skipped"
    }

    /// Deliberately blind to `isEnabled`: that guard lives in the coordinator, and only there.
    static func make(
        layout: WindowLayout, screens: [WindowLayoutScreen], windows: [WindowLayoutWindow],
        preferredGap: CGFloat
    ) -> WindowLayoutPlan {
        let gap = layout.usesPreferredGap ? preferredGap : 0
        var screensByUUID: [String: WindowLayoutScreen] = [:]
        for screen in screens where screensByUUID[screen.display.uuid.lowercased()] == nil {
            screensByUUID[screen.display.uuid.lowercased()] = screen
        }
        var available = Dictionary(grouping: sorted(windows), by: \.bundleID)
        var launched: Set<String> = []
        var placements: [Placement] = []
        var skipped: [Skipped] = []

        for entry in layout.entries {
            guard let target = screensByUUID[entry.display.uuid.lowercased()] else {
                skipped.append(
                    Skipped(
                        entryID: entry.id, reason: .displayDisconnected(name: entry.display.name)))
                continue
            }
            guard
                let frame = WindowLayoutGeometry.resolve(entry, on: target.screen, gap: gap)
            else {
                skipped.append(Skipped(entryID: entry.id, reason: .unresolvableGeometry))
                continue
            }

            let source: Source
            if entry.argument == nil,
                let index = nearest(to: frame, among: available[entry.bundleID] ?? [])
            {
                source = .existing(handle: available[entry.bundleID]!.remove(at: index).handle)
            } else {
                // Opening the same app with the same argument twice yields one window, not two.
                let key = entry.bundleID + "\u{0}" + (entry.argument ?? "")
                guard launched.insert(key).inserted else {
                    skipped.append(Skipped(entryID: entry.id, reason: .duplicateTarget))
                    continue
                }
                source = .launch
            }

            placements.append(
                Placement(
                    entryID: entry.id, bundleID: entry.bundleID, argument: entry.argument,
                    source: source, frame: frame, screenID: target.screen.id, anchor: entry.anchor,
                    canvas: WindowLayoutGeometry.box(target.screen, gap: gap)))
        }
        return WindowLayoutPlan(placements: placements, skipped: skipped)
    }

    /// Nearest centre wins, so an already-correct desktop is a no-op and nothing swaps displays.
    private static func nearest(to frame: CGRect, among windows: [WindowLayoutWindow]) -> Int? {
        var best: (index: Int, distance: CGFloat)?
        for (index, window) in windows.enumerated() {
            let distance =
                abs(window.frame.midX - frame.midX) + abs(window.frame.midY - frame.midY)
            if distance < (best?.distance ?? .infinity) { best = (index, distance) }
        }
        return best?.index
    }

    /// Reading order, so shuffling the inventory cannot change the plan.
    private static func sorted(_ windows: [WindowLayoutWindow]) -> [WindowLayoutWindow] {
        windows.sorted {
            if $0.frame.minY != $1.frame.minY { return $0.frame.minY < $1.frame.minY }
            if $0.frame.minX != $1.frame.minX { return $0.frame.minX < $1.frame.minX }
            if $0.title != $1.title { return $0.title < $1.title }
            return $0.handle < $1.handle
        }
    }
}
