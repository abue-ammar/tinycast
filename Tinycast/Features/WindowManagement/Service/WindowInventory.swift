import AppKit
@preconcurrency import ApplicationServices

/// Reads what is on screen over AX, once, through a single `AXGeometry` snapshot.
@MainActor
enum WindowInventory {
    /// A snapshot walks every app, so one hung process must not cost the full mover timeout.
    private static let sweepTimeout: Float = 0.2

    /// Live AX handles for one window. Never `Sendable`: these do not leave the main actor.
    struct Element {
        let bundleID: String
        let application: AXUIElement
        let window: AXUIElement
    }

    struct Snapshot {
        var screens: [WindowLayoutScreen]
        /// The pure description the plan works from; `handle` indexes `elements`.
        var windows: [WindowLayoutWindow]
        var elements: [Int: Element]
    }

    /// `positionableOnly` is the capture path: a window we could never move is not an entry.
    static func snapshot(positionableOnly: Bool = false) -> Snapshot {
        let geometry = AXGeometry(screens: NSScreen.screens)
        var windows: [WindowLayoutWindow] = []
        var elements: [Int: Element] = [:]

        for app in candidates() {
            guard let bundleID = app.bundleIdentifier else { continue }
            let application = AXWindowAccess.application(
                for: app.processIdentifier, timeout: sweepTimeout)
            for window in AXWindowAccess.windows(in: application) {
                AXUIElementSetMessagingTimeout(window, sweepTimeout)
                guard let frame = eligibleFrame(window, positionableOnly: positionableOnly)
                else { continue }
                let handle = windows.count
                windows.append(
                    WindowLayoutWindow(
                        handle: handle, bundleID: bundleID, frame: frame,
                        title: AXWindowAccess.string(window, kAXTitleAttribute) ?? ""))
                elements[handle] = Element(
                    bundleID: bundleID, application: application, window: window)
            }
        }
        return Snapshot(
            screens: AXScreens.layoutScreens(geometry: geometry), windows: windows,
            elements: elements)
    }

    /// The windows of one app that this run has not already written to.
    static func unclaimedWindows(
        of application: AXUIElement, excluding claimed: [AXUIElement]
    ) -> [AXUIElement] {
        AXWindowAccess.windows(in: application).filter { window in
            AXUIElementSetMessagingTimeout(window, sweepTimeout)
            guard eligibleFrame(window, positionableOnly: true) != nil else { return false }
            return !claimed.contains { CFEqual($0, window) }
        }
    }

    /// Every app with a user-facing window, bar us. By pid, since About flips us to `.regular`.
    static func candidates() -> [NSRunningApplication] {
        let ownPID = NSRunningApplication.current.processIdentifier
        return NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular && !$0.isTerminated
                && $0.processIdentifier != ownPID
        }
    }

    static func application(for bundleID: String) -> (AXUIElement, NSRunningApplication)? {
        guard
            let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
                .first(where: { !$0.isTerminated })
        else { return nil }
        return (AXWindowAccess.application(for: app.processIdentifier), app)
    }

    /// A window a layout may name: real, standard, on screen, and reporting geometry.
    private static func eligibleFrame(
        _ window: AXUIElement, positionableOnly: Bool
    ) -> CGRect? {
        // Stricter than the mover's rule: a Save sheet must never be captured as an entry.
        guard
            AXWindowAccess.string(window, kAXSubroleAttribute)
                == (kAXStandardWindowSubrole as String)
        else { return nil }
        guard AXWindowAccess.bool(window, kAXMinimizedAttribute) != true,
            !AXWindowAccess.isFullScreen(window), let frame = AXWindowAccess.frame(of: window),
            frame.width > 0, frame.height > 0
        else { return nil }
        guard !positionableOnly || AXWindowAccess.isSettable(kAXPositionAttribute, on: window)
        else { return nil }
        return frame
    }
}
