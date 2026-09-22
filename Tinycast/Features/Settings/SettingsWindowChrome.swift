import AppKit

/// The window flags `NSHostingController` can't bridge; SwiftUI owns the toolbar and its title.
@MainActor
final class SettingsWindowChrome: WindowChrome {
    func install(in window: NSWindow) {
        // All three together are what puts the title inline and leading rather than centred.
        window.titleVisibility = .visible
        window.toolbarStyle = .unified
        // `.automatic` draws a hairline once content scrolls under the bar, splitting the surface.
        window.titlebarSeparatorStyle = .none
        // Transparent opts the titlebar out of the system's glass band; Settings wants it drawn.
        window.titlebarAppearsTransparent = false
        // Stock Settings isn't dragged by its content — a drag on a `Form` shouldn't move the window.
        window.isMovableByWindowBackground = false
    }
}
