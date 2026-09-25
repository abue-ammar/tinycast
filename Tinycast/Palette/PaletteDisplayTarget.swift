import AppKit

@MainActor
enum PaletteDisplayTarget {
    private static var didPromptForAccessibility = false

    static func screen(for display: PaletteDisplay) -> NSScreen? {
        let screens = NSScreen.screens
        let geometry = AXGeometry(screens: screens)
        let converted = AXScreens.converted(screens, geometry: geometry)
        let mouse = NSEvent.mouseLocation
        let mouseIndex = screens.firstIndex { NSMouseInRect(mouse, $0.frame, false) }
        let frame = display == .focusedWindow ? focusedWindowFrame() : nil
        guard let selected = PaletteDisplaySelection.screen(
            for: display, screens: converted,
            mouseScreenID: mouseIndex.map { converted[$0].id }, focusedWindowFrame: frame),
            let index = converted.firstIndex(where: { $0.id == selected.id })
        else { return nil }
        return screens[index]
    }

    private static func focusedWindowFrame() -> CGRect? {
        guard Permissions.isAccessibilityTrusted() else {
            if !didPromptForAccessibility {
                didPromptForAccessibility = true
                Permissions.ensureAccessibility()
            }
            return nil
        }
        return AXWindowAccess.focusedExternalWindowFrame(timeout: 0.05)
    }
}
