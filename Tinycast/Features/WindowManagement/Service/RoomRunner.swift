// Adapted from Rooms (MIT): https://github.com/saragordic/rooms/blob/main/LICENSE
import AppKit
@preconcurrency import ApplicationServices

/// Walks into a room: its windows land on one display, everything else steps back. See window-rooms.md.
@MainActor
enum RoomRunner {
    /// Long enough for a cold app to draw, short enough a stuck one cannot hold the room.
    private static let launchDeadline = Duration.seconds(10)
    /// A just-unhidden app ignores moves, and reports no windows, until it is really back.
    private static let unhideDeadline = Duration.milliseconds(600)
    /// Unhiding is a cheap flag to poll; a launch wait sweeps every app, so it polls slowly.
    private static let unhidePoll = Duration.milliseconds(20)
    private static let launchPoll = Duration.milliseconds(200)
    /// Apps that animate a resize are still mid-way this soon after the write.
    private static let settleDelay = Duration.milliseconds(150)
    /// Long enough for a late or bounced frame to show before the one correction.
    private static let verifyDelay = Duration.milliseconds(250)
    /// Raises across apps land in order only when each app has a moment to come forward.
    private static let raisePacing = Duration.milliseconds(40)
    /// A new minimum can reveal another in a narrower slot; minimums only grow, so this ends.
    private static let relayoutPasses = 2
    /// Slack for an app's own rounding, such as a terminal sizing in whole cells.
    private static let slack: CGFloat = 4
    private static let resizeSlack: CGFloat = 16

    struct Context {
        let gap: CGFloat
        /// Where the room lands; its first connected display when that one is gone.
        let displayUUID: String?
        let claimed: Set<UInt32>
        let minimums: RoomMinimumSizeStore
        let ledger: RoomParkingLedger
    }

    struct Outcome: Sendable {
        var placed = 0
        var parked = 0
        /// The apps this pass hid, so only they come back later, never one hidden by hand.
        var hiddenApps = Set<pid_t>()
        var missing: [String] = []
        var isBlockedOnPermission = false
    }

    // MARK: - Entering

    static func enter(_ room: Room, context: Context) async -> Outcome {
        guard Permissions.ensureAccessibility() else { return Outcome(isBlockedOnPermission: true) }
        let apps = appsInOrder(of: room)
        let launched = launchMissing(apps)
        let unhidden = unhide(apps)
        await wait(for: unhideDeadline, every: unhidePoll) { unhidden.allSatisfy { !$0.isHidden } }

        var snapshot = RoomWindowSweep.snapshot()
        guard var plan = makePlan(room, in: snapshot, context: context) else { return Outcome() }
        let late = launched.union(unhidden.compactMap(\.bundleIdentifier))
        if !late.isEmpty {
            await wait(for: launched.isEmpty ? unhideDeadline : launchDeadline, every: launchPoll) {
                guard plan.missing.contains(where: { late.contains(room.windows[$0].bundleID) })
                else { return true }
                snapshot = RoomWindowSweep.snapshot()
                plan = makePlan(room, in: snapshot, context: context) ?? plan
                return false
            }
        }
        let missing = plan.missing.map { room.windows[$0].appName }
        // With nothing to show, stepping everything back would leave an empty desk.
        guard !Task.isCancelled, !plan.placements.isEmpty else { return Outcome(missing: missing) }

        place(plan.placements, in: snapshot)
        for _ in 0..<relayoutPasses {
            try? await Task.sleep(for: settleDelay)
            guard await learnMinimums(from: plan, in: snapshot, into: context.minimums) else { break }
            snapshot = RoomWindowSweep.snapshot()
            guard let replanned = makePlan(room, in: snapshot, context: context) else { break }
            plan = replanned
            place(plan.placements, in: snapshot)
        }

        var outcome = Outcome(placed: plan.placements.count, missing: missing)
        outcome.parked = park(plan, in: snapshot, ledger: context.ledger)
        returnWindowsOfHiddenApps(plan, in: snapshot, ledger: context.ledger)
        await raise(plan, in: snapshot)
        outcome.hiddenApps = hideApps(keeping: plan.keeps)

        try? await Task.sleep(for: verifyDelay)
        verify(plan, in: snapshot, minimums: context.minimums)
        forgetPlacedWindows(plan, in: snapshot, ledger: context.ledger)
        return outcome
    }

    /// The apps rooms hid, then every parked window: a just-unhidden app ignores moves until back.
    static func restoreEverything(hiddenApps: Set<pid_t>, ledger: RoomParkingLedger) async {
        let hidden = WindowInventory.candidates().filter {
            $0.isHidden && hiddenApps.contains($0.processIdentifier)
        }
        hidden.forEach(show)
        await wait(for: unhideDeadline, every: unhidePoll) { hidden.allSatisfy { !$0.isHidden } }
        returnParkedWindows(ledger: ledger)
    }

    /// Every parked window home, how many came back. Synchronous, so quitting runs it through.
    @discardableResult
    static func returnParkedWindows(ledger: RoomParkingLedger) -> Int {
        guard Permissions.isAccessibilityTrusted(), !ledger.isEmpty else { return 0 }
        let snapshot = RoomWindowSweep.snapshot()
        let screens = snapshot.screens.map(\.screen.frame)
        let returned = snapshot.windows.compactMap { window -> UInt32? in
            guard let element = snapshot.elements[window.handle] else { return nil }
            return unpark(window, element: element, screens: screens, ledger: ledger)
        }
        ledger.forget(returned)
        // A quit app's windows went with it; one that is running but slow keeps its way back.
        ledger.keepOnly(
            bundleIDs: Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier)))
        return returned.count
    }

    // MARK: - Planning

    private static func makePlan(
        _ room: Room, in snapshot: RoomWindowSweep.Snapshot, context: Context
    ) -> RoomPlan? {
        guard let screen = snapshot.screen(uuid: context.displayUUID) else { return nil }
        return RoomPlan.make(
            room, windows: snapshot.windows, on: screen, gap: context.gap,
            minimums: context.minimums.sizes, claimed: context.claimed)
    }

    private static func appsInOrder(of room: Room) -> [String] {
        var seen = Set<String>()
        return room.windows.map(\.bundleID).filter { seen.insert($0).inserted }
    }

    private static func launchMissing(_ bundleIDs: [String]) -> Set<String> {
        var launched = Set<String>()
        for bundleID in bundleIDs
        where NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty {
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
            else { continue }
            AppLauncher.launch(url)
            launched.insert(bundleID)
        }
        return launched
    }

    private static func unhide(_ bundleIDs: [String]) -> [NSRunningApplication] {
        let wanted = Set(bundleIDs)
        let hidden = WindowInventory.candidates().filter {
            $0.isHidden && wanted.contains($0.bundleIdentifier ?? "")
        }
        hidden.forEach(show)
        return hidden
    }

    /// Polls inside the gesture's own task; `ContinuousClock`, so a clock step cannot shorten it.
    private static func wait(
        for duration: Duration, every interval: Duration, until isDone: () -> Bool
    ) async {
        let deadline = ContinuousClock.now + duration
        while !isDone(), ContinuousClock.now < deadline, !Task.isCancelled {
            try? await Task.sleep(for: interval, tolerance: interval)
        }
    }

    // MARK: - Placing

    /// No `await` between windows, so the room lands in one visible step.
    private static func place(
        _ placements: [RoomPlan.Placement], in snapshot: RoomWindowSweep.Snapshot
    ) {
        let targets = placements.compactMap { placement in
            snapshot.elements[placement.handle].map { (frame: placement.frame, element: $0) }
        }
        // One suppress and restore per application: the flag is application-scoped.
        for group in Dictionary(grouping: targets, by: { $0.element.app.processIdentifier }).values {
            let restore = AXWindowAccess.suppressEnhancedUserInterface(on: group[0].element.application)
            defer { restore() }
            for target in group { write(target.frame, to: target.element.window) }
        }
    }

    private static func write(_ frame: CGRect, to window: AXUIElement) {
        AXUIElementSetMessagingTimeout(window, AXWindowAccess.messagingTimeout)
        if AXWindowAccess.bool(window, kAXMinimizedAttribute) == true {
            _ = AXWindowAccess.unminimize(window)
        }
        // Checked before any write, so an unpositionable window is left untouched.
        guard AXWindowAccess.isSettable(kAXPositionAttribute, on: window),
            let current = AXWindowAccess.frame(of: window)
        else { return }
        _ = AXWindowAccess.write(
            frame, anchor: .topLeading, to: window, current: current,
            canResize: AXWindowAccess.isSettable(kAXSizeAttribute, on: window), canvas: nil)
    }

    /// AX reports no minimum size, so a refused resize teaches it; a second ask rules out a lag.
    private static func learnMinimums(
        from plan: RoomPlan, in snapshot: RoomWindowSweep.Snapshot, into store: RoomMinimumSizeStore
    ) async -> Bool {
        let refusing = plan.placements.filter { placement in
            guard let window = snapshot.elements[placement.handle]?.window,
                let actual = AXWindowAccess.frame(of: window)
            else { return false }
            return exceeds(actual.size, placement.frame.size)
        }
        guard !refusing.isEmpty else { return false }
        for placement in refusing {
            guard let window = snapshot.elements[placement.handle]?.window else { continue }
            _ = AXWindowAccess.setSize(placement.frame.size, on: window)
        }
        try? await Task.sleep(for: settleDelay)
        var learned = false
        for placement in refusing {
            guard let element = snapshot.elements[placement.handle],
                let actual = AXWindowAccess.frame(of: element.window)
            else { continue }
            let wanted = placement.frame.size
            let refused = CGSize(
                width: actual.width > wanted.width + slack ? actual.width : 0,
                height: actual.height > wanted.height + slack ? actual.height : 0)
            if store.learn(refused, for: element.bundleID) { learned = true }
        }
        return learned
    }

    private static func exceeds(_ actual: CGSize, _ wanted: CGSize) -> Bool {
        actual.width > wanted.width + slack || actual.height > wanted.height + slack
    }

    /// Back to front, one app at a time, so the main window ends on top and focused.
    private static func raise(_ plan: RoomPlan, in snapshot: RoomWindowSweep.Snapshot) async {
        let elements = plan.placements.compactMap { snapshot.elements[$0.handle] }
        guard let main = elements.first else { return }
        for element in elements.dropFirst().reversed() {
            AXWindowAccess.raise(element.window, in: element.application)
            try? await Task.sleep(for: raisePacing)
        }
        AXWindowAccess.focus(main.window, in: main.application, of: main.app)
    }

    /// One correction for a frame applied late or bounced back; no loop, which would jitter.
    private static func verify(
        _ plan: RoomPlan, in snapshot: RoomWindowSweep.Snapshot, minimums: RoomMinimumSizeStore
    ) {
        let off = plan.placements.filter { placement in
            guard let element = snapshot.elements[placement.handle],
                let actual = AXWindowAccess.frame(of: element.window)
            else { return false }
            return !lands(actual, on: placement.frame, minimum: minimums.size(for: element.bundleID))
        }
        place(off, in: snapshot)
    }

    /// Close enough: within an app's rounding, or larger only by a minimum it is known to keep.
    private static func lands(_ actual: CGRect, on wanted: CGRect, minimum: CGSize) -> Bool {
        let width =
            abs(actual.width - wanted.width) <= resizeSlack
            || actual.width <= max(wanted.width, minimum.width) + slack
        let height =
            abs(actual.height - wanted.height) <= resizeSlack
            || actual.height <= max(wanted.height, minimum.height) + slack
        return width && height && abs(actual.minX - wanted.minX) <= slack
            && abs(actual.minY - wanted.minY) <= slack
    }

    // MARK: - Stepping back

    /// A window without an ID, or whose way back failed to write, stays put rather than risk loss.
    private static func park(
        _ plan: RoomPlan, in snapshot: RoomWindowSweep.Snapshot, ledger: RoomParkingLedger
    ) -> Int {
        let screens = snapshot.screens.map(\.screen)
        var parked = 0
        for handle in plan.parks {
            guard let window = snapshot.window(handle), let element = snapshot.elements[handle],
                let windowID = window.windowID,
                let host = WindowPlacementEngine.screen(containing: window.frame, in: screens)
                    ?? screens.first,
                ledger.record(
                    RoomParkingLedger.Entry(
                        windowID: windowID, bundleID: window.bundleID, title: window.title,
                        frame: window.frame))
            else { continue }
            let others = screens.filter { $0.id != host.id }.map(\.frame)
            let origin = RoomParking.origin(
                for: window.frame.size, on: host.visibleFrame, avoiding: others)
            if AXWindowAccess.setPosition(origin, on: element.window) { parked += 1 }
        }
        return parked
    }

    /// An app about to hide takes its windows with it, so none of them may stay parked.
    private static func returnWindowsOfHiddenApps(
        _ plan: RoomPlan, in snapshot: RoomWindowSweep.Snapshot, ledger: RoomParkingLedger
    ) {
        let staying = Set(plan.placements.map(\.handle)).union(plan.parks)
        let screens = snapshot.screens.map(\.screen.frame)
        let returned = snapshot.windows.compactMap { window -> UInt32? in
            guard !staying.contains(window.handle), let element = snapshot.elements[window.handle]
            else { return nil }
            return unpark(window, element: element, screens: screens, ledger: ledger)
        }
        ledger.forget(returned)
    }

    /// The window's ID once it is back home; nil leaves its way back on disk for the next try.
    private static func unpark(
        _ window: RoomLiveWindow, element: WindowInventory.Element, screens: [CGRect],
        ledger: RoomParkingLedger
    ) -> UInt32? {
        guard let windowID = window.windowID, let entry = ledger.entry(for: windowID),
            entry.bundleID == window.bundleID
        else { return nil }
        let home = RoomParking.returnFrame(for: entry.frame, screens: screens)
        let restore = AXWindowAccess.suppressEnhancedUserInterface(on: element.application)
        defer { restore() }
        write(home, to: element.window)
        guard let now = AXWindowAccess.frame(of: element.window),
            abs(now.minX - home.minX) <= resizeSlack, abs(now.minY - home.minY) <= resizeSlack
        else { return nil }
        return windowID
    }

    /// The active app cannot hide, which is why the room's main window is focused first.
    private static func hideApps(keeping keeps: Set<String>) -> Set<pid_t> {
        var hidden = Set<pid_t>()
        for app in WindowInventory.candidates()
        where !app.isHidden && !keeps.contains(app.bundleIdentifier ?? "") {
            if !app.hide() {
                AXWindowAccess.setHidden(
                    true, application: AXWindowAccess.application(for: app.processIdentifier))
            }
            hidden.insert(app.processIdentifier)
        }
        return hidden
    }

    /// A window parked earlier is forgotten only once it is confirmed mostly inside its place.
    private static func forgetPlacedWindows(
        _ plan: RoomPlan, in snapshot: RoomWindowSweep.Snapshot, ledger: RoomParkingLedger
    ) {
        let back = plan.placements.compactMap { placement -> UInt32? in
            guard let windowID = snapshot.window(placement.handle)?.windowID,
                ledger.entry(for: windowID) != nil,
                let window = snapshot.elements[placement.handle]?.window,
                let actual = AXWindowAccess.frame(of: window)
            else { return nil }
            let shared = actual.intersection(placement.frame)
            let area = placement.frame.width * placement.frame.height
            return !shared.isNull && shared.width * shared.height >= area / 2 ? windowID : nil
        }
        ledger.forget(back)
    }

    private static func show(_ app: NSRunningApplication) {
        guard !app.unhide() else { return }
        AXWindowAccess.setHidden(
            false, application: AXWindowAccess.application(for: app.processIdentifier))
    }
}
