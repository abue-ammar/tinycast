// Adapted from Rooms (MIT): https://github.com/saragordic/rooms/blob/main/LICENSE
import AppKit
import SwiftUI

/// One window-to-be in the preview. The same window keeps the same id, so its card can glide.
struct RoomPreviewCard: Identifiable, Equatable {
    let id: String
    /// AX coordinates, the space the plan resolves in.
    var frame: CGRect
    var appName: String
    var title: String
    var appURL: URL?
}

/// What every display's preview panel draws: the cards back to front, and the palette to avoid.
@MainActor
@Observable
final class RoomPreviewModel {
    var cards: [RoomPreviewCard] = []
    /// The palette's frame in AX space, which a card's icon stays out from under.
    var avoiding: CGRect?
}

/// Owns the preview's panels: one click-through panel per display, just under the palette.
@MainActor
final class RoomPreviewController {
    private let model = RoomPreviewModel()
    private var panels: [RoomPreviewPanel] = []

    var isShowing: Bool { !panels.isEmpty }

    /// `cards` back to front; `avoiding` is the palette's frame in screen coordinates.
    func show(_ cards: [RoomPreviewCard], avoiding: CGRect?) {
        let geometry = AXGeometry(screens: NSScreen.screens)
        model.avoiding = avoiding.map(geometry.flip)
        guard isShowing else {
            model.cards = cards
            open(geometry: geometry)
            return
        }
        let glide = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? nil : Theme.RoomMotion.glide
        withAnimation(glide) { model.cards = cards }
    }

    /// `settling` is the hold after ↵: the windows move in under the preview, then it fades.
    func hide(settling: Bool = false) {
        guard isShowing else { return }
        let closing = panels
        panels = []
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            closing.forEach { $0.orderOut(nil) }
            model.cards = []
            return
        }
        let duration = settling ? Theme.Duration.roomSettle : Theme.Duration.exit
        for panel in closing {
            panel.fadeOut(duration: duration) { [weak self] in
                // A show that began during the fade owns the cards now.
                guard let self, !self.isShowing else { return }
                self.model.cards = []
            }
        }
    }

    private func open(geometry: AXGeometry) {
        panels = NSScreen.screens.map { screen in
            let frame = geometry.flip(screen.frame)
            let host = NSHostingView(
                rootView: RoomPreviewView(model: model, origin: frame.origin, size: frame.size))
            // The controller owns the frame; without this the hosting view would size the window.
            host.sizingOptions = []
            let panel = RoomPreviewPanel()
            panel.contentView = host
            panel.setFrame(screen.frame, display: false)
            return panel
        }
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        for panel in panels {
            if reduceMotion {
                panel.orderFrontRegardless()
            } else {
                panel.fadeIn(duration: Theme.Duration.roomCardEnter) { panel.orderFrontRegardless() }
            }
        }
    }
}

/// Borderless, click-through, never key: the preview is a readout drawn under the palette.
private final class RoomPreviewPanel: NSPanel {
    init() {
        super.init(
            contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .paletteDropGuide
        ignoresMouseEvents = true
        hidesOnDeactivate = false
        animationBehavior = .none
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isReleasedWhenClosed = false
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
