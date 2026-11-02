import AppKit
import SwiftUI

/// Owns the standalone camera surface: one panel at a time, and the camera stops with it.
@MainActor
@Observable
final class CameraCoordinator {
    private(set) var feed: CameraSession.Feed = .noCamera
    private(set) var canSwitchCamera = false
    /// Remembered for the launch, so reopening the command keeps the framing you were happy with.
    var mirrored = true

    @ObservationIgnored private let session = CameraSession(.capture)
    @ObservationIgnored private unowned let core: AppCore
    @ObservationIgnored private var panel: CameraPanel?
    /// Held across the camera warm-up too, so a chord repeating into it cannot stack panels.
    @ObservationIgnored private var opening = false

    init(core: AppCore) {
        self.core = core
    }

    /// The camera settles first: a panel over a starting session shows a black stage.
    func show() async {
        // A panel system UI left without key takes it back, so ↵ and Esc reach it again.
        if let panel {
            panel.makeKey()
            return
        }
        guard !opening else { return }
        opening = true
        defer { opening = false }
        feed = await session.start()
        canSwitchCamera = session.hasMultipleDevices
        present()
    }

    func close() {
        guard let closing = panel else { return }
        panel = nil
        closing.onAction = nil
        // The camera goes with the panel, not before it: tearing it down mid-close blanks the feed.
        closing.orderOutAnimated { [weak self] in
            // Unless a panel raised inside the close already owns the camera.
            guard let self, !opening, panel == nil else { return }
            session.stop()
        }
    }

    func switchCamera() {
        Task { await session.switchToNextDevice() }
    }

    /// The panel goes with the shot: the command is done, and the camera light goes out with it.
    func takePhoto() {
        guard case .live = feed else { return }
        let mirrored = mirrored
        let shooting = panel
        Task {
            let png = await session.capturePhoto(mirrored: mirrored)
            if panel === shooting { close() }
            guard let png else {
                core.showMessage(String(localized: "Couldn't take the photo"), tone: .danger)
                return
            }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setData(png, forType: .png)
            core.showMessage(String(localized: "Photo copied"))
        }
    }

    private func present() {
        let hosting = NSHostingView(rootView: CameraView(coordinator: self).motionScope())
        hosting.setFrameSize(hosting.fittingSize)
        let panel = CameraPanel(content: hosting)
        panel.onAction = { [weak self] action in
            guard let self else { return }
            if action == .primary { takePhoto() } else { close() }
        }
        self.panel = panel
        panel.centerOnCursorScreen()
        // Non-activating like the palette: key focus without pulling the user out of their app.
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
    }
}
