import AppKit
import SwiftUI

/// Shows the drop guides over one screen for the length of a drag. The window controller drives it;
/// nothing else may, since only a live drag has a home placement to point at.
@MainActor
final class PaletteDropGuideController {
    private var panel: NSPanel?
    private var host: NSHostingView<PaletteDropGuideView>?
    private var screenFrame: CGRect = .zero
    private var home: CGPoint = .zero
    private var armed = false

    /// Reveal the guides, with `home` the default placement's top-left in screen coordinates.
    func show(home: CGPoint, screenFrame: CGRect, armed: Bool) {
        self.home = home
        self.screenFrame = screenFrame
        self.armed = armed
        let panel = ensurePanel()
        panel.setFrame(screenFrame, display: false)
        render()
        panel.orderFrontRegardless()
    }

    /// Re-point mid-drag. `windowDidMove` fires continuously, so an unchanged move costs nothing.
    func move(home: CGPoint, screenFrame: CGRect) {
        guard self.home != home || self.screenFrame != screenFrame else { return }
        let crossedScreens = self.screenFrame != screenFrame
        self.home = home
        self.screenFrame = screenFrame
        if crossedScreens { panel?.setFrame(screenFrame, display: false) }
        render()
    }

    func setArmed(_ armed: Bool) {
        guard self.armed != armed else { return }
        self.armed = armed
        render()
    }

    func hide() {
        panel?.orderOut(nil)
    }

    // MARK: - Private

    /// One step under `.floating`, so the guides clear other apps but never the panel being dragged.
    private static let level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue - 1)

    private func ensurePanel() -> NSPanel {
        if let panel { return panel }
        let host = NSHostingView(rootView: guides)
        // The controller owns the frame; without this the hosting view would size the window.
        host.sizingOptions = []
        let panel = PaletteDropGuidePanel(level: Self.level)
        panel.contentView = host
        self.host = host
        self.panel = panel
        return panel
    }

    private func render() {
        host?.rootView = guides
    }

    /// AppKit's y grows up from the screen's origin, SwiftUI's grows down from the window's top.
    private var guides: PaletteDropGuideView {
        PaletteDropGuideView(
            topLeft: CGPoint(x: home.x - screenFrame.minX, y: screenFrame.maxY - home.y),
            width: Theme.Size.panelWidth,
            armed: armed)
    }
}

/// Borderless, click-through, never key: the guides are a readout, not a surface.
private final class PaletteDropGuidePanel: NSPanel {
    init(level: NSWindow.Level) {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        self.level = level
        ignoresMouseEvents = true
        hidesOnDeactivate = false
        animationBehavior = .none
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isReleasedWhenClosed = false
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
