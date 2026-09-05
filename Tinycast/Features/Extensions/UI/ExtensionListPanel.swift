import AppKit
import SwiftUI

/// A picker's own window, so its glass samples the desktop exactly as the ⌘K menu's does.
final class ExtensionListPanel: NSPanel {
    weak var paletteState: PaletteState?

    /// Key stays with the palette: the control below keeps first responder and drives this list.
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

    /// Mirrors `MenuPanel`: rows light on real pointer movement, never on a scroll under it.
    override func sendEvent(_ event: NSEvent) {
        switch event.type {
        case .mouseMoved: paletteState?.notePointerMoved(to: NSEvent.mouseLocation)
        case .scrollWheel: paletteState?.disarmHoverHighlight(pointerAt: NSEvent.mouseLocation)
        default: break
        }
        super.sendEvent(event)
    }
}

/// Presents one control's list at a time in a panel hung off the palette window.
@MainActor
final class ExtensionListPanelController {
    private var panel: ExtensionListPanel?
    private var hosting: NSHostingView<AnyView>?

    func present(_ content: AnyView, frame: NSRect, parent: NSWindow, palette: PaletteState) {
        let panel = ensurePanel(state: palette)
        if let hosting {
            hosting.rootView = content
        } else {
            let view = NSHostingView(rootView: content)
            // The frame is stated from the control's place, so the host may never size the window.
            view.sizingOptions = []
            panel.contentView = view
            hosting = view
        }
        if panel.frame != frame { panel.setFrame(frame, display: true) }
        guard panel.parent == nil else { return }
        // A list opened by key lands under the pointer, which chose no row of it.
        palette.disarmHoverHighlight(pointerAt: NSEvent.mouseLocation)
        parent.addChildWindow(panel, ordered: .above)
    }

    func hide() {
        guard let panel else { return }
        panel.parent?.removeChildWindow(panel)
        panel.orderOut(nil)
        // Dropped, not parked: the hosted tree captures the control that owns this controller.
        panel.contentView = nil
        hosting = nil
        self.panel = nil
    }

    private func ensurePanel(state: PaletteState) -> ExtensionListPanel {
        if let panel {
            panel.paletteState = state
            return panel
        }
        let panel = ExtensionListPanel()
        panel.paletteState = state
        self.panel = panel
        return panel
    }
}

/// Where a list lands on screen, and which way it opened for the chevron that reports it.
struct ExtensionListPlacement: Equatable {
    let frame: NSRect
    let flipped: Bool

    /// The shipped rule in screen space; the palette's frame stays the room a list may fill.
    @MainActor
    init?(anchor: CGRect, in window: NSWindow, height: CGFloat) {
        guard let contentHeight = window.contentView?.bounds.height else { return nil }
        let host = window.frame
        // SwiftUI reports the control top-left down; AppKit reads the window bottom-left up.
        let control = window.convertToScreen(
            NSRect(
                x: anchor.minX, y: contentHeight - anchor.maxY, width: anchor.width,
                height: anchor.height))
        let placement = ExtensionFormMetrics.placement(
            anchor: CGRect(
                x: control.minX, y: host.maxY - control.maxY, width: control.width,
                height: control.height),
            popoverHeight: height, containerHeight: host.height)
        frame = NSRect(
            x: control.minX, y: host.maxY - placement.y - height,
            width: ExtensionFormMetrics.controlWidth, height: height)
        flipped = placement.flipped
    }
}

/// Reports the window a control is hosted in, without reaching for the palette's own reader.
struct ExtensionWindowProbe: NSViewRepresentable {
    let onResolve: (NSWindow?) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = ProbeView()
        view.onResolve = onResolve
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        (view as? ProbeView)?.onResolve = onResolve
    }

    private final class ProbeView: NSView {
        var onResolve: ((NSWindow?) -> Void)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            onResolve?(window)
        }
    }
}

/// Drives one control's list panel from the state the control already holds.
private struct ExtensionListPanelModifier<List: View, Revision: Equatable>: ViewModifier {
    let open: Bool
    let height: CGFloat
    /// Whatever the drawn list depends on, so a keystroke that changes it repaints the panel.
    let revision: Revision
    @Binding var flipped: Bool
    let list: () -> List

    @State private var controller = ExtensionListPanelController()
    @State private var host: NSWindow?
    @State private var anchor: CGRect = .zero
    @Environment(PaletteState.self) private var palette

    private struct Key: Equatable {
        let open: Bool
        let height: CGFloat
        let anchor: CGRect
        let revision: Revision
    }

    func body(content: Content) -> some View {
        content
            .background { ExtensionWindowProbe { host = $0 } }
            // Global, not the form's space: the panel is placed in screen coordinates.
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { anchor = $0 }
            .onChange(of: Key(open: open, height: height, anchor: anchor, revision: revision)) {
                sync()
            }
            .onAppear { sync() }
            .onDisappear { controller.hide() }
    }

    private func sync() {
        guard open, let host, anchor.width > 0,
            let placement = ExtensionListPlacement(anchor: anchor, in: host, height: height)
        else {
            controller.hide()
            return
        }
        if flipped != placement.flipped { flipped = placement.flipped }
        let root = AnyView(list().environment(palette))
        controller.present(root, frame: placement.frame, parent: host, palette: palette)
    }
}

extension View {
    /// Opens this control's list in a window of its own, as the ⌘K menu is opened.
    func extensionListPanel<List: View, Revision: Equatable>(
        open: Bool, height: CGFloat, revision: Revision, flipped: Binding<Bool>,
        @ViewBuilder list: @escaping () -> List
    ) -> some View {
        modifier(
            ExtensionListPanelModifier(
                open: open, height: height, revision: revision, flipped: flipped, list: list))
    }
}
