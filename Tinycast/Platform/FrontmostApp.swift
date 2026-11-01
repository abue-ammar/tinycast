import AppKit

/// The app an action is for: a link that activates accessory Tinycast leaves it the menu bar.
@MainActor
enum FrontmostApp {
    static var current: NSRunningApplication? {
        let workspace = NSWorkspace.shared
        guard let frontmost = workspace.frontmostApplication,
            frontmost.processIdentifier == NSRunningApplication.current.processIdentifier
        else { return workspace.frontmostApplication }
        return workspace.menuBarOwningApplication ?? frontmost
    }
}
