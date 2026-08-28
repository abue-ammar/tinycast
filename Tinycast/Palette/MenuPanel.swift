import AppKit
import SwiftUI

/// The ⌘K menu's own window, so glass renders against the desktop and nothing clips it.
final class MenuPanel: NSPanel {
    weak var paletteState: PaletteState?

    /// Key stays with the palette: its `onKeyPress` handlers drive this menu's selection.
    override var canBecomeKey: Bool { false }

    init() {
        super.init(
            contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false)
        isFloatingPanel = true
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        acceptsMouseMovedEvents = true
        ignoresMouseEvents = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    }

    /// Mirrors `PalettePanel`: rows light on real pointer movement, never on a scroll under it.
    override func sendEvent(_ event: NSEvent) {
        switch event.type {
        case .mouseMoved: paletteState?.notePointerMoved(to: NSEvent.mouseLocation)
        case .scrollWheel: paletteState?.disarmHoverHighlight(pointerAt: NSEvent.mouseLocation)
        default: break
        }
        super.sendEvent(event)
    }
}

/// Presents one menu at a time in a `MenuPanel` hung off a corner of the palette.
@MainActor
final class MenuPanelController {
    /// Where a menu hangs from, in the palette's own terms.
    enum Corner {
        case bottomLeading
        case bottomTrailing
        case belowHeaderTrailing
    }

    private var panel: MenuPanel?
    private var hosting: NSHostingView<AnyView>?
    private weak var parent: NSWindow?

    /// Inset from the palette's corners, so the menu's own corner isn't flush with the panel's.
    private static let inset: CGFloat = 8

    var isOpen: Bool { panel?.isVisible ?? false }

    func show(_ content: AnyView, corner: Corner, parent: NSWindow, core: AppCore) {
        let root = AnyView(content.paletteEnvironment(core))
        let panel = ensurePanel(state: core.palette)
        if let hosting {
            hosting.rootView = root
        } else {
            let view = NSHostingView(rootView: root)
            view.sizingOptions = [.intrinsicContentSize]
            panel.contentView = view
            hosting = view
        }
        self.parent = parent
        layout(corner: corner, parent: parent)
        guard panel.parent == nil else { return }
        parent.addChildWindow(panel, ordered: .above)
    }

    /// Rebuilds the hosted tree in place: the panel keeps its window, so nothing flickers.
    func update(_ content: AnyView, corner: Corner, core: AppCore) {
        guard let hosting, let parent else { return }
        hosting.rootView = AnyView(content.paletteEnvironment(core))
        layout(corner: corner, parent: parent)
    }

    func hide() {
        guard let panel else { return }
        panel.parent?.removeChildWindow(panel)
        panel.orderOut(nil)
    }

    private func ensurePanel(state: PaletteState) -> MenuPanel {
        if let panel {
            panel.paletteState = state
            return panel
        }
        let panel = MenuPanel()
        panel.paletteState = state
        self.panel = panel
        return panel
    }

    /// Sizes to the hosted menu, then seats it against the palette's frame in screen space.
    private func layout(corner: Corner, parent: NSWindow) {
        guard let panel, let hosting else { return }
        let size = hosting.intrinsicContentSize
        guard size.width > 0, size.height > 0 else { return }
        let host = parent.frame
        let origin: NSPoint =
            switch corner {
            case .bottomLeading:
                NSPoint(x: host.minX + Self.inset, y: host.minY + Self.inset)
            case .bottomTrailing:
                NSPoint(x: host.maxX - Self.inset - size.width, y: host.minY + Self.inset)
            case .belowHeaderTrailing:
                NSPoint(
                    x: host.maxX - Theme.Spacing.md * 2 - size.width,
                    y: host.maxY - Theme.Size.headerPadding - Theme.Size.headerHeight - size.height)
            }
        let frame = NSRect(origin: origin, size: size)
        // Every arrow key re-pushes the tree, and only the highlight moved.
        guard panel.frame != frame else { return }
        panel.setFrame(frame, display: true)
    }
}
