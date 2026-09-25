import Foundation

/// The Rooms screens' state while one is open: the desk read once, and the picker's choice.
@MainActor
@Observable
final class RoomSession {
    /// An app a room holds without naming a window: opened on entry, kept visible.
    struct App: Hashable, Sendable {
        var bundleID: String
        var name: String
        var url: URL?
    }

    /// One member of the room being picked, in room order.
    enum Pick: Hashable, Sendable {
        case window(handle: Int)
        case app(App)
    }

    /// Bumped when a sweep lands, so a preview drawn from the last desk is redrawn.
    private(set) var revision = 0
    private(set) var isLoaded = false
    /// Every window the picker offers: visible ones front to back, then parked, hidden, minimized.
    private(set) var pickable: [RoomLiveWindow] = []
    /// Room order; the first is the main window.
    private(set) var picked: [Pick] = []
    /// The room the picker edits, or nil for a new one.
    private(set) var editingID: UUID?
    /// The picker's search field filters, so the room's name is held here.
    private(set) var roomName = ""
    /// Live AX handles, so they are never observed and never outlive the screen.
    @ObservationIgnored private(set) var snapshot: RoomWindowSweep.Snapshot?

    func present(_ snapshot: RoomWindowSweep.Snapshot, parked: Set<UInt32>) {
        self.snapshot = snapshot
        pickable = snapshot.windows.sorted { lhs, rhs in
            let left = Self.pickingTier(lhs, parked: parked)
            let right = Self.pickingTier(rhs, parked: parked)
            return left != right ? left < right : (lhs.frontRank, lhs.handle) < (rhs.frontRank, rhs.handle)
        }
        isLoaded = true
        revision &+= 1
    }

    func beginPicking(named name: String, editing id: UUID?, picked picks: [Pick]) {
        roomName = name
        editingID = id
        picked = picks
    }

    func togglePick(_ pick: Pick) {
        if let index = picked.firstIndex(of: pick) {
            picked.remove(at: index)
        } else {
            picked.append(pick)
        }
    }

    func reset() {
        snapshot = nil
        pickable = []
        picked = []
        editingID = nil
        roomName = ""
        isLoaded = false
    }

    private static func pickingTier(_ window: RoomLiveWindow, parked: Set<UInt32>) -> Int {
        if window.isAppHidden || window.isMinimized { return 2 }
        return window.windowID.map(parked.contains) == true ? 1 : 0
    }
}
