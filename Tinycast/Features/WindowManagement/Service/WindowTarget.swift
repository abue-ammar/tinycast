import AppKit

/// What a window command places. See docs/features/window-management.md#choosing-a-target.
@MainActor
enum WindowTarget {
    case external(NSRunningApplication)
    case own(NSWindow)

    /// Our panels never activate, so the frontmost app is not what the user is looking at.
    static func current() -> WindowTarget? {
        if let own = NSApp.keyWindow.flatMap(placeable) { return .own(own) }
        return NSWorkspace.shared.frontmostApplication.map(WindowTarget.external)
    }

    /// The same answer from what the palette recorded when it covered the screen.
    static func behindPalette(
        ownWindow: NSWindow?, app: NSRunningApplication?
    ) -> WindowTarget? {
        if let own = ownWindow.flatMap(placeable) { return .own(own) }
        return app.map(WindowTarget.external)
    }

    /// The window, or its parent: the note switcher is a key child of the editor it sits over.
    private static func placeable(_ window: NSWindow) -> NSWindow? {
        [window, window.parent].compactMap { $0 }.first(where: isPlaceable)
    }

    /// Every transient panel in the app declines `canBecomeMain`, which leaves the real windows.
    private static func isPlaceable(_ window: NSWindow) -> Bool {
        window.isVisible && window.canBecomeMain && window.isMovable
    }
}
