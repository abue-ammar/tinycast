import AppKit

/// Keyed by window identity, not a count: a repeated open or close can't strand the Dock icon.
@MainActor
final class ActivationPolicy {
    private var openWindows: Set<ObjectIdentifier> = []

    var hasOpenWindows: Bool { !openWindows.isEmpty }

    /// Off keeps Tinycast an accessory even while windows are open, so it never enters the Dock.
    var showsDockIcon = true {
        didSet {
            guard showsDockIcon != oldValue, hasOpenWindows else { return }
            NSApp.setActivationPolicy(showsDockIcon ? .regular : .accessory)
            // Leaving `.regular` deactivates the app, which would drop the window the user is in.
            if !showsDockIcon { NSApp.activate() }
        }
    }

    /// Before the window exists: one built first joins a fullscreen Space its menus never reach.
    func windowWillOpen() {
        if showsDockIcon { NSApp.setActivationPolicy(.regular) }
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
