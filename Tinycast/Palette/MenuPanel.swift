import AppKit
import SwiftUI

/// The ⌘K menu's own window, so glass renders against the desktop and nothing clips it.
final class MenuPanel: NSPanel, AnimatedPanel {
    weak var paletteState: PaletteState?
    var onKeyDown: ((NSEvent) -> Bool)?
    var onResignKey: ((_ stayedInPalette: Bool) -> Void)?

    override var canBecomeKey: Bool { true }

    init() {
        super.init(
            contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false)
        isFloatingPanel = true
        followMotion()
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
        case .keyDown, .scrollWheel:
            paletteState?.disarmHoverHighlight(pointerAt: NSEvent.mouseLocation)
        case .flagsChanged:
            paletteState?.noteCommandHeld(event.modifierFlags.contains(.command))
        default: break
        }
        if event.type == .keyDown, onKeyDown?(event) == true {
            return
        }
        super.sendEvent(event)
    }

    override func resignKey() {
        super.resignKey()
        paletteState?.noteCommandHeld(false)
        guard onKeyDown != nil else { return }
        let presentation = paletteState?.menuPresentationToken
        Task { @MainActor [weak self] in
            await Task.yield()
            guard let self, onKeyDown != nil, !isKeyWindow,
                paletteState?.menuPresentationToken == presentation
            else { return }
            onResignKey?(parent?.isKeyWindow == true)
        }
    }

}

/// Presents one menu at a time in a `MenuPanel` hung off a corner of the palette.
@MainActor
final class MenuPanelController {
    /// The geometry `layout` last applied, as requested rather than as AppKit rounded it.
    private struct Placement: Equatable {
        let frame: CGRect
        let corner: MenuPanelCorner
    }

    private var panel: MenuPanel?
    private var hosting: NSHostingView<AnyView>?
    private weak var parent: NSWindow?
    private var placement: Placement?

    var isOpen: Bool { panel?.isVisible ?? false }

    func show(
        _ content: AnyView, corner: MenuPanelCorner, parent: NSWindow, core: AppCore,
        onKeyDown: @escaping (NSEvent) -> Bool, onDismiss: @escaping () -> Void
    ) {
        let panel = ensurePanel(state: core.palette)
        configureCallbacks(
            for: panel, core: core, onKeyDown: onKeyDown, onDismiss: onDismiss)
        setContent(AnyView(content.paletteEnvironment(core)), in: panel)
        self.parent = parent
        (parent as? PalettePanel)?.onDismissMenu = onDismiss
        // Open disarmed: a menu opened by click lands under the pointer, which chose no row of it.
        core.palette.disarmHoverHighlight(pointerAt: NSEvent.mouseLocation)
        layout(
            corner: corner, parent: parent, metrics: core.settings.interfaceSize.metrics,
            force: true)
        if panel.parent == nil { parent.addChildWindow(panel, ordered: .above) }
        panel.makeKey()
        refreshShadow(panel)
    }

    /// Rebuilds the hosted tree in place: the panel keeps its window, so nothing flickers.
    func update(_ content: AnyView, corner: MenuPanelCorner, core: AppCore) {
        guard let panel, panel.isVisible, let parent else { return }
        setContent(AnyView(content.paletteEnvironment(core)), in: panel)
        layout(
            corner: corner, parent: parent, metrics: core.settings.interfaceSize.metrics,
            force: false)
    }

    private func setContent(_ root: AnyView, in panel: MenuPanel) {
        if let hosting {
            hosting.rootView = root
            return
        }
        let view = NSHostingView(rootView: root)
        view.sizingOptions = [.intrinsicContentSize]
        let container = NSView(frame: .zero)
        container.addSubview(view)
        panel.contentView = container
        // AppKit owns the hosting layer's first layout; let it settle before ours.
        panel.displayIfNeeded()
        hosting = view
    }

    private func configureCallbacks(
        for panel: MenuPanel, core: AppCore, onKeyDown: @escaping (NSEvent) -> Bool,
        onDismiss: @escaping () -> Void
    ) {
        panel.onKeyDown = onKeyDown
        panel.onResignKey = { [weak core] stayedInPalette in
            if stayedInPalette {
                onDismiss()
            } else {
                core?.paletteCoordinator.hidePalette(restoreFocus: false)
            }
        }
    }

    private func refreshShadow(_ panel: MenuPanel) {
        hosting?.layoutSubtreeIfNeeded()
        panel.displayIfNeeded()
        panel.invalidateShadow()
    }

    func hide() {
        (parent as? PalettePanel)?.onDismissMenu = nil
        guard let panel else { return }
        panel.onKeyDown = nil
        panel.onResignKey = nil
        if panel.isKeyWindow { parent?.makeKey() }
        // A hidden child must detach or AppKit restores it with its parent on the next summon.
        panel.parent?.removeChildWindow(panel)
        panel.orderOutAnimated { [weak self] in self?.releaseHiddenContent() }
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

    /// A menu reopened during the close animation keeps the tree it was given.
    private func releaseHiddenContent() {
        guard panel?.isVisible == false else { return }
        hosting?.rootView = AnyView(EmptyView())
    }

    private func layout(
        corner: MenuPanelCorner, parent: NSWindow, metrics: InterfaceMetrics, force: Bool
    ) {
        guard let panel, let hosting else { return }
        let size = hosting.intrinsicContentSize
        guard size.width > 0, size.height > 0 else { return }
        // `bottomBar`'s own padding: a menu's edge must line up with the button it hangs off.
        let inset = metrics.spacing.md
        let frame = corner.frame(
            contentSize: size, parentFrame: parent.frame,
            visibleFrame: parent.screen?.visibleFrame ?? parent.frame, inset: inset,
            headerExtent: metrics.size.headerPadding + metrics.size.headerHeight)
        let next = Placement(frame: frame, corner: corner)
        guard force || next != placement else { return }
        placement = next
        panel.setFrame(frame, display: true)
        hosting.frame = NSRect(origin: .zero, size: size)
        refreshShadow(panel)
    }
}
