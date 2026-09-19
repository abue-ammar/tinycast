import AppKit
import SwiftUI

/// The ⌘K menu's own window, so glass renders against the desktop and nothing clips it.
final class MenuPanel: NSPanel {
    weak var paletteState: PaletteState?
    var onKeyDown: ((NSEvent) -> Bool)?
    var onResignKey: ((_ stayedInPalette: Bool) -> Void)?

    override var canBecomeKey: Bool { true }

    init() {
        super.init(
            contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false)
        isFloatingPanel = true
        animationBehavior = .none
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
        Task { @MainActor [weak self] in
            await Task.yield()
            guard let self, onKeyDown != nil else { return }
            onResignKey?(parent?.isKeyWindow == true)
        }
    }

}

/// Presents one menu at a time in a `MenuPanel` hung off a corner of the palette.
@MainActor
final class MenuPanelController {
    /// The geometry `layout` last applied, as requested rather than as AppKit rounded it.
    private struct Placement: Equatable {
        let canvas: CGRect
        let corner: MenuPanelCorner
    }

    private var panel: MenuPanel?
    private var hosting: NSHostingView<AnyView>?
    private weak var parent: NSWindow?
    private var clipPath: MenuPanelClipPath?
    private var placement: Placement?
    private var modelScale: CGFloat = 1
    private var reducesMotion = false
    private var motion: MenuPanelMotion?
    private var transition: UInt64 = 0

    var isOpen: Bool { panel?.isVisible ?? false }
    private(set) var isClosing = false

    func show(
        _ content: AnyView, corner: MenuPanelCorner, parent: NSWindow, core: AppCore,
        clipPath: @escaping MenuPanelClipPath, motion: MenuPanelMotion,
        onKeyDown: @escaping (NSEvent) -> Bool, onDismiss: @escaping () -> Void
    ) {
        let transition = beginTransition(closing: false)
        self.motion = motion
        reducesMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        modelScale = reducesMotion ? 1 : motion.entryScale
        let panel = ensurePanel(state: core.palette)
        let wasVisible = panel.isVisible
        configureCallbacks(
            for: panel, core: core, onKeyDown: onKeyDown, onDismiss: onDismiss)
        panel.cancelFade()
        panel.alphaValue = 0
        let root = AnyView(content.paletteEnvironment(core))
        setContent(root, clipPath: clipPath, in: panel)
        self.parent = parent
        panel.ignoresMouseEvents = false
        // Open disarmed: a menu opened by click lands under the pointer, which chose no row of it.
        core.palette.disarmHoverHighlight(pointerAt: NSEvent.mouseLocation)
        layout(
            corner: corner, parent: parent, metrics: core.settings.metrics,
            resetMotion: true)
        if !wasVisible, panel.parent == nil { parent.addChildWindow(panel, ordered: .above) }
        startReveal(in: panel, transition: transition, motion: motion)
        panel.makeKey()
        refreshShadow(panel)
    }

    /// Rebuilds the hosted tree in place: the panel keeps its window, so nothing flickers.
    func update(
        _ content: AnyView, corner: MenuPanelCorner, core: AppCore,
        clipPath: @escaping MenuPanelClipPath, motion: MenuPanelMotion
    ) {
        guard let panel, let parent, !isClosing else { return }
        self.motion = motion
        setContent(
            AnyView(content.paletteEnvironment(core)),
            clipPath: clipPath, in: panel)
        layout(
            corner: corner, parent: parent, metrics: core.settings.metrics,
            resetMotion: false)
    }

    private func setContent(
        _ root: AnyView, clipPath: @escaping MenuPanelClipPath, in panel: MenuPanel
    ) {
        self.clipPath = clipPath
        if let hosting {
            hosting.rootView = root
            return
        }
        let view = NSHostingView(rootView: root)
        view.sizingOptions = [.intrinsicContentSize]
        view.wantsLayer = true
        view.layer?.allowsEdgeAntialiasing = true
        let container = NSView(frame: .zero)
        container.addSubview(view)
        panel.contentView = container
        // AppKit owns the hosting layer's first layout; let it settle before applying our anchor.
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

    private func startReveal(
        in panel: MenuPanel, transition: UInt64, motion: MenuPanelMotion
    ) {
        Task { @MainActor [weak self, weak panel] in
            await Task.yield()
            guard let self, let panel, panel.parent != nil,
                isCurrent(transition, closing: false)
            else { return }
            panel.displayIfNeeded()
            animatePanelAlpha(
                panel, to: 1, duration: motion.expansionDuration + motion.settleDuration,
                timing: motion.expansionTiming
            ) { [weak self, weak panel] in
                guard let self, let panel, isCurrent(transition, closing: false) else { return }
                refreshShadow(panel)
            }
            guard !reducesMotion else { return }
            animateScale(
                from: motion.entryScale,
                to: motion.maximumScale,
                duration: motion.expansionDuration,
                timing: motion.expansionTiming
            ) { [weak self, weak panel] in
                guard let self, let panel, panel.isVisible,
                    isCurrent(transition, closing: false)
                else { return }
                animateScale(
                    to: 1, duration: motion.settleDuration,
                    timing: motion.settleTiming)
            }
        }
    }

    func hide() {
        guard let panel else {
            cancelTransitions()
            return
        }
        panel.onKeyDown = nil
        panel.onResignKey = nil
        if panel.isKeyWindow { parent?.makeKey() }
        // A hidden child must detach or AppKit restores it with its parent on the next summon.
        guard panel.isVisible else {
            cancelTransitions()
            detach(panel)
            return
        }
        guard !isClosing, let motion else { return }
        let transition = beginTransition(closing: true)
        panel.ignoresMouseEvents = true
        Task { @MainActor [weak self, weak panel] in
            // Defer until Escape's SwiftUI transaction settles, or it can absorb the animation.
            await Task.yield()
            guard let self, let panel, isCurrent(transition, closing: true)
            else { return }
            guard panel.isVisible else {
                finishDismissal(panel, transition: transition)
                return
            }
            startDismissalAnimation(in: panel, transition: transition, motion: motion)
        }
    }

    private func finishDismissal(_ panel: MenuPanel, transition: UInt64) {
        guard isCurrent(transition, closing: true) else { return }
        isClosing = false
        detach(panel)
    }

    private func beginTransition(closing: Bool) -> UInt64 {
        transition &+= 1
        isClosing = closing
        return transition
    }

    private func cancelTransitions() {
        _ = beginTransition(closing: false)
    }

    private func isCurrent(_ transition: UInt64, closing: Bool) -> Bool {
        self.transition == transition && isClosing == closing
    }

    private func detach(_ panel: MenuPanel) {
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
    private func layout(
        corner: MenuPanelCorner, parent: NSWindow, metrics: InterfaceMetrics, resetMotion: Bool
    ) {
        guard let panel, let hosting, let motion else { return }
        let size = hosting.intrinsicContentSize
        guard size.width > 0, size.height > 0 else { return }
        // `bottomBar`'s own padding: a menu's edge must line up with the button it hangs off.
        let inset = metrics.spacing.md
        let frame = corner.frame(
            contentSize: size, parentFrame: parent.frame, inset: inset,
            headerExtent: metrics.size.headerPadding + metrics.size.headerHeight)
        let canvas = corner.scaledFrame(frame, by: motion.maximumScale)
        let next = Placement(canvas: canvas, corner: corner)
        // Every arrow key re-pushes the tree; reconfiguring would cut the reveal short.
        guard resetMotion || next != placement else { return }
        placement = next
        panel.setFrame(canvas, display: true)
        configureHosting(
            contentSize: size, canvasSize: canvas.size, scale: modelScale, corner: corner,
            metrics: metrics)
        refreshShadow(panel)
    }

    private func startDismissalAnimation(
        in panel: MenuPanel, transition: UInt64, motion: MenuPanelMotion
    ) {
        guard let layer = hosting?.layer else {
            finishDismissal(panel, transition: transition)
            return
        }
        let visible = layer.presentation() ?? layer
        let startScale = CGFloat(visible.transform.m11)
        let minimumScale = motion.entryScale - motion.exitScaleDelta
        let targetScale =
            reducesMotion ? startScale : max(minimumScale, startScale - motion.exitScaleDelta)
        if !reducesMotion {
            animateScale(to: targetScale, duration: motion.exitDuration, timing: motion.exitTiming)
        }
        animatePanelAlpha(
            panel, to: 0, duration: motion.exitDuration, timing: motion.exitTiming
        ) { [weak self, weak panel] in
            guard let self, let panel else { return }
            finishDismissal(panel, transition: transition)
        }
    }

    private func animateScale(
        from start: CGFloat? = nil, to target: CGFloat, duration: TimeInterval,
        timing: CAMediaTimingFunction, completion: (@MainActor () -> Void)? = nil
    ) {
        guard let layer = hosting?.layer else { return }
        let transform = CATransform3DMakeScale(target, target, 1)
        let animation = CABasicAnimation(keyPath: "transform")
        let startTransform =
            start.map { CATransform3DMakeScale($0, $0, 1) }
            ?? (layer.presentation() ?? layer).transform
        animation.fromValue = NSValue(caTransform3D: startTransform)
        animation.toValue = NSValue(caTransform3D: transform)
        animation.duration = duration
        animation.timingFunction = timing

        modelScale = target
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if let completion {
            CATransaction.setCompletionBlock {
                Task { @MainActor in completion() }
            }
        }
        layer.transform = transform
        layer.add(animation, forKey: "menuScale")
        CATransaction.commit()
    }

    private func animatePanelAlpha(
        _ panel: MenuPanel, to alpha: CGFloat, duration: TimeInterval,
        timing: CAMediaTimingFunction, completion: @escaping @MainActor () -> Void
    ) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            context.timingFunction = timing
            panel.animator().alphaValue = alpha
        } completionHandler: {
            MainActor.assumeIsolated { completion() }
        }
    }

    private func configureHosting(
        contentSize: NSSize, canvasSize: NSSize, scale: CGFloat, corner: MenuPanelCorner,
        metrics: InterfaceMetrics
    ) {
        guard let hosting, let layer = hosting.layer, let clipPath else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.removeAllAnimations()
        layer.setAffineTransform(.identity)
        hosting.frame = NSRect(origin: .zero, size: contentSize)
        layer.bounds = NSRect(origin: .zero, size: contentSize)
        layer.anchorPoint = corner.layerAnchor
        layer.position = corner.layerPosition(in: canvasSize)
        let mask = (layer.mask as? CAShapeLayer) ?? CAShapeLayer()
        mask.frame = NSRect(origin: .zero, size: contentSize)
        mask.isGeometryFlipped = layer.isGeometryFlipped
        mask.path = clipPath(mask.bounds, metrics, corner)
        layer.mask = mask
        layer.setAffineTransform(CGAffineTransform(scaleX: scale, y: scale))
        CATransaction.commit()
    }
}
