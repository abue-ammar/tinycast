import AppKit

/// The app an action is for: a link that activates accessory Tinycast leaves it the menu bar.
@MainActor
enum FrontmostApp {
    static var current: NSRunningApplication? {
        let workspace = NSWorkspace.shared
        // With a window of ours in key, the reader is in Tinycast, not wherever the menu bar is.
        guard let frontmost = workspace.frontmostApplication,
            frontmost.processIdentifier == NSRunningApplication.current.processIdentifier,
            NSApp.keyWindow == nil
        else { return workspace.frontmostApplication }
        return workspace.menuBarOwningApplication ?? frontmost
    }
}
