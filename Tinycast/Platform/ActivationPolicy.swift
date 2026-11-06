import AppKit

/// Keyed by window identity, not a count: a repeated open or close can't strand the Dock icon.
@MainActor
final class ActivationPolicy {
    private var openWindows: Set<ObjectIdentifier> = []

    var hasOpenWindows: Bool { !openWindows.isEmpty }

    /// Before the window exists: one built first joins a fullscreen Space its menus never reach.
    func windowWillOpen() {
        NSApp.setActivationPolicy(.regular)
    }

    func windowDidOpen(_ window: NSWindow) {
        openWindows.insert(ObjectIdentifier(window))
    }

    func windowDidClose(_ window: NSWindow) {
        openWindows.remove(ObjectIdentifier(window))
        if openWindows.isEmpty { NSApp.setActivationPolicy(.accessory) }
    }

    /// Each close reports back through `windowDidClose`, which drops the Dock icon after the last.
    func closeAll() {
        for window in NSApp.windows where openWindows.contains(ObjectIdentifier(window)) {
            window.close()
        }
    }
}
