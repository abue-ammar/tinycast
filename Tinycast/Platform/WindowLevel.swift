import AppKit

extension NSWindow.Level {
    /// Above `.modalPanel`, where other apps' open panels and sheets-as-windows sit.
    static let palette = NSWindow.Level(rawValue: NSWindow.Level.modalPanel.rawValue + 1)
    /// One step under the palette, so guides clear other apps but not the dragged panel.
    static let paletteDropGuide = NSWindow.Level(rawValue: palette.rawValue - 1)
    /// Above the palette, so a confirmation is never buried under its trigger.
    static let dialog = NSWindow.Level(rawValue: palette.rawValue + 1)
}
