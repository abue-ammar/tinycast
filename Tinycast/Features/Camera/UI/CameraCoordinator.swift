import AppKit
import SwiftUI

/// Owns the palette's camera screen: the camera runs only while that screen is on screen.
@MainActor
@Observable
final class CameraCoordinator {
    /// Nil while the camera warms up, which the screen shows as its own transition.
    private(set) var feed: CameraSession.Feed?
    private(set) var canSwitchCamera = false
    /// Remembered for the launch, so reopening the command keeps the framing you were happy with.
    var mirrored = true

    @ObservationIgnored private let session = CameraSession(.capture)
    @ObservationIgnored private unowned let core: AppCore
    /// Bumped by every load and stop, so a start that settles late is dropped rather than shown.
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var requestingAccess = false

    init(core: AppCore) {
        self.core = core
    }

    /// The TCC prompt takes key, which would dismiss a palette already up, so it is asked first.
    func show() {
        guard Permissions.cameraAccess() == .notDetermined else {
            core.paletteCoordinator.togglePalette(mode: .camera)
            return
        }
        guard !requestingAccess else { return }
        requestingAccess = true
        core.paletteCoordinator.hidePalette()
        Task {
            _ = await Permissions.requestCameraAccess()
            requestingAccess = false
            core.paletteCoordinator.showPalette(mode: .camera)
        }
    }

    /// Every open starts anew, a restored screen included: hiding stopped the last session.
    func load() {
        generation += 1
        let current = generation
        feed = nil
        Task {
            let settled = await session.start()
            guard current == generation else { return }
            canSwitchCamera = session.hasMultipleDevices
            feed = settled
        }
    }

    func stop() {
        generation += 1
        feed = nil
        session.stop()
    }

    func switchCamera() {
        Task { await session.switchToNextDevice() }
    }

    /// The palette goes with the shot: the command is done, and the camera light goes out with it.
    func takePhoto() {
        guard case .live = feed else { return }
        let mirrored = mirrored
        Task {
            let png = await session.capturePhoto(mirrored: mirrored)
            if core.paletteCoordinator.isShowing(.camera) { core.paletteCoordinator.hidePalette() }
            guard let png else {
                core.showMessage("Couldn't take the photo", tone: .danger)
                return
            }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setData(png, forType: .png)
            core.showMessage("Photo copied")
        }
    }
}
