import AppKit
@preconcurrency import ApplicationServices

/// Applies a layout in one pass: place what exists, open what doesn't, place that too.
@MainActor
enum WindowLayoutRunner {
    /// Long enough for a cold app to draw, short enough a stuck one can't hold the run.
    private static let launchDeadline = Duration.seconds(10)
    /// An AX round trip per pending app per tick, so this is deliberately not per-frame.
    private static let pollInterval = Duration.milliseconds(200)

    struct Outcome: Sendable {
        var placed = 0
        var opened = 0
        var skipped: [WindowLayoutPlan.Skipped] = []
        /// Apps that opened but never produced a window before the deadline.
        var neverAppeared: [String] = []
        /// Launch failures, already localised by `QuicklinkLauncher`.
        var openFailures: [String] = []
        /// The grant is missing, which is the one failure the user must act on.
        var isBlockedOnPermission = false

        var didAnything: Bool { placed > 0 }
    }

    /// The one entry point. `gap` is the preferred gap; the layout decides whether to use it.
    static func run(_ layout: WindowLayout, gap: CGFloat) async -> Outcome {
        // An explicit user gesture, so prompting for the grant is appropriate here.
        guard Permissions.ensureAccessibility() else {
            return Outcome(isBlockedOnPermission: true)
        }

        let snapshot = WindowInventory.snapshot()
        let plan = WindowLayoutPlan.make(
            layout: layout, screens: snapshot.screens, windows: snapshot.windows,
            preferredGap: gap)
        var outcome = Outcome(skipped: plan.skipped)
        guard !plan.placements.isEmpty else { return outcome }

        let startingApp = NSWorkspace.shared.frontmostApplication?.processIdentifier
        var bound: [UUID: WindowInventory.Element] = [:]
        placeExisting(plan, snapshot: snapshot, bound: &bound, outcome: &outcome)

        let pending = plan.opens
        if !pending.isEmpty {
            await open(pending, outcome: &outcome)
            await placeOpened(pending, bound: &bound, outcome: &outcome)
        }
        // Last, so no app this run opened can activate over the one the layout names.
        if !Task.isCancelled, let frontmost = plan.frontmostEntryID.flatMap({ bound[$0] }),
            !userSwitchedApps(since: startingApp, opening: pending)
        {
            AXWindowAccess.focus(frontmost.window, in: frontmost.application, of: frontmost.app)
        }
        return outcome
    }

    /// A launch taking the front is expected; any other app there means the user moved on.
    private static func userSwitchedApps(
        since startingApp: pid_t?, opening placements: [WindowLayoutPlan.Placement]
    ) -> Bool {
        guard let current = NSWorkspace.shared.frontmostApplication,
            current.processIdentifier != startingApp
        else { return false }
        return !placements.contains { $0.bundleID == current.bundleIdentifier }
    }

    /// Every window a layout could name, with the focused one marked to end a run frontmost.
    static func captureCurrentWindows() -> (entries: [WindowLayoutEntry], frontmostEntryID: UUID?) {
        guard Permissions.ensureAccessibility() else { return ([], nil) }
        let snapshot = WindowInventory.snapshot(positionableOnly: true)
        let screens = snapshot.screens
        let focusedHandle = focusedWindowHandle(in: snapshot)
        var frontmostEntryID: UUID?
        let entries = snapshot.windows.compactMap { window -> WindowLayoutEntry? in
            guard
                let host = WindowPlacementEngine.screen(
                    containing: window.frame, in: screens.map(\.screen)),
                let target = screens.first(where: { $0.screen.id == host.id })
            else { return nil }
            let entry = WindowLayoutGeometry.entry(
                bundleID: window.bundleID, display: target.display, frame: window.frame,
                on: target.screen)
            if window.handle == focusedHandle { frontmostEntryID = entry.id }
            return entry
        }
        return (entries, frontmostEntryID)
    }

    /// Nil when Tinycast itself is frontmost, as it is when capturing from Settings.
    private static func focusedWindowHandle(in snapshot: WindowInventory.Snapshot) -> Int? {
        guard let app = NSWorkspace.shared.frontmostApplication,
            let focused = AXWindowAccess.element(
                AXWindowAccess.application(for: app.processIdentifier),
                kAXFocusedWindowAttribute)
        else { return nil }
        return snapshot.elements.first { _, element in
            element.app.processIdentifier == app.processIdentifier
                && CFEqual(element.window, focused)
        }?.key
    }

    // MARK: - Placing

    /// One suppress/restore per application, not per window: the flag is application-scoped.
    private static func placeExisting(
        _ plan: WindowLayoutPlan, snapshot: WindowInventory.Snapshot,
        bound: inout [UUID: WindowInventory.Element], outcome: inout Outcome
    ) {
        let existing = plan.placements.filter { $0.source != .launch }
        for (_, group) in Dictionary(grouping: existing, by: \.bundleID) {
            guard case .existing(let first) = group[0].source,
                let application = snapshot.elements[first]?.application
            else { continue }
            let restore = AXWindowAccess.suppressEnhancedUserInterface(on: application)
            defer { restore() }
            for placement in group {
                guard case .existing(let handle) = placement.source,
                    let element = snapshot.elements[handle]
                else { continue }
                if place(placement, on: element.window) { outcome.placed += 1 }
                bound[placement.entryID] = element
            }
        }
    }

    private static func place(
        _ placement: WindowLayoutPlan.Placement, on window: AXUIElement
    ) -> Bool {
        AXUIElementSetMessagingTimeout(window, AXWindowAccess.messagingTimeout)
        // Checked before any write, so an unpositionable window is left untouched.
        guard AXWindowAccess.isSettable(kAXPositionAttribute, on: window),
            let current = AXWindowAccess.frame(of: window)
        else { return false }
        let canResize = AXWindowAccess.isSettable(kAXSizeAttribute, on: window)
        return AXWindowAccess.write(
            placement.frame, anchor: placement.anchor.placement, to: window, current: current,
            canResize: canResize, canvas: placement.canvas) != nil
    }

    // MARK: - Opening

    private static func open(
        _ placements: [WindowLayoutPlan.Placement], outcome: inout Outcome
    ) async {
        for placement in placements {
            guard
                let url = NSWorkspace.shared.urlForApplication(
                    withBundleIdentifier: placement.bundleID)
            else {
                outcome.openFailures.append(placement.bundleID)
                continue
            }
            guard let argument = placement.argument else {
                AppLauncher.launch(url)
                outcome.opened += 1
                continue
            }
            do {
                // The same open a quicklink makes, so a path, a host and a deeplink all behave.
                try await QuicklinkLauncher.open(
                    argument, openWithBundleID: placement.bundleID, inNewWindow: false)
                outcome.opened += 1
            } catch {
                outcome.openFailures.append(error.localizedDescription)
            }
        }
    }

    /// A bounded wait inside this gesture's own task: no timer, no observer, nothing left behind.
    private static func placeOpened(
        _ placements: [WindowLayoutPlan.Placement],
        bound: inout [UUID: WindowInventory.Element], outcome: inout Outcome
    ) async {
        var pending = placements
        // `ContinuousClock`, so a clock step or a sleep cannot shorten or extend the wait.
        let deadline = ContinuousClock.now + launchDeadline
        while !pending.isEmpty, ContinuousClock.now < deadline, !Task.isCancelled {
            try? await Task.sleep(for: pollInterval, tolerance: pollInterval)
            guard !Task.isCancelled else { break }
            pending = pending.filter { placement in
                guard let (application, app) = WindowInventory.application(for: placement.bundleID),
                    let window = WindowInventory.unclaimedWindows(
                        of: application, excluding: bound.values.lazy.map(\.window)
                    ).first
                else { return true }
                let restore = AXWindowAccess.suppressEnhancedUserInterface(on: application)
                defer { restore() }
                if place(placement, on: window) { outcome.placed += 1 }
                bound[placement.entryID] = WindowInventory.Element(
                    bundleID: placement.bundleID, app: app, application: application,
                    window: window)
                return false
            }
        }
        outcome.neverAppeared = pending.map(\.bundleID)
    }
}
