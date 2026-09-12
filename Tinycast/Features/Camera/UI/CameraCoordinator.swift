import AppKit
import SwiftUI

/// Owns the standalone camera surface: one panel at a time, and the camera stops with it.
@MainActor
@Observable
final class CameraCoordinator: NSObject, NSWindowDelegate {
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
        guard !opening, panel == nil else { return }
        opening = true
        defer { opening = false }
        feed = await session.start()
        canSwitchCamera = session.hasMultipleDevices
        present()
    }

    func close() {
        guard let closing = panel else { return }
        panel = nil
        closing.delegate = nil
        closing.onKey = nil
        // The camera goes with the panel, not before it: tearing it down mid-fade blanks the feed.
        closing.fadeOut(duration: Theme.Duration.exit) { [weak self] in
            // Unless a panel raised inside the fade already owns the camera.
            guard let self, !opening else { return }
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
        Task {
            let png = await session.capturePhoto(mirrored: mirrored)
            close()
            guard let png else {
                core.showMessage("Couldn't take the photo", tone: .danger)
                return
            }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setData(png, forType: .png)
            core.showMessage("Photo copied")
        }
    }

    private func present() {
        let hosting = NSHostingView(rootView: CameraView(coordinator: self))
        hosting.setFrameSize(hosting.fittingSize)
        let panel = CameraPanel(content: hosting)
        panel.delegate = self
        panel.onKey = { [weak self] key in
            guard let self else { return }
            if key == .primary { takePhoto() } else { close() }
        }
        self.panel = panel
        panel.centerOnCursorScreen()
        // Non-activating like the palette: key focus without pulling the user out of their app.
        panel.fadeIn(duration: Theme.Duration.enter) {
            panel.makeKeyAndOrderFront(nil)
            panel.orderFrontRegardless()
        }
    }

    // MARK: - NSWindowDelegate

    /// Click-away closes rather than leaving a camera running behind another window.
    func windowDidResignKey(_ notification: Notification) {
        guard let panel, notification.object as? NSWindow === panel else { return }
        close()
    }
}
