import SwiftUI

/// The standalone camera: a live stage, a mirror switch, and a photo straight to the clipboard.
struct CameraView: View {
    let coordinator: CameraCoordinator

    var body: some View {
        VStack(spacing: 0) {
            CameraStage(feed: coordinator.feed, mirrored: coordinator.mirrored)
                .frame(
                    width: Theme.Size.cameraStage.width,
                    height: Theme.Size.cameraStage.height)
            footer
        }
        .frame(width: Theme.Size.cameraStage.width)
        .background(Theme.Colors.panelScrim)
        .background(VisualEffectView())
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.dialog, style: .continuous))
        .panelEntrance()
    }

    private var isLive: Bool {
        if case .live = coordinator.feed { return true }
        return false
    }

    private var footer: some View {
        HStack(spacing: Theme.Spacing.md) {
            if isLive {
                CameraButton(
                    title: "Mirror", emphasis: coordinator.mirrored ? .primary : .secondary
                ) {
                    coordinator.mirrored.toggle()
                }
                if coordinator.canSwitchCamera {
                    CameraButton(title: "Switch Camera", emphasis: .secondary) {
                        coordinator.switchCamera()
                    }
                }
            }
            Spacer(minLength: Theme.Spacing.md)
            CameraButton(title: "Close", keyCap: "esc", emphasis: .secondary) {
                coordinator.close()
            }
            if isLive {
                CameraButton(title: "Take Photo", keyCap: "↵") { coordinator.takePhoto() }
            }
        }
        .padding(Theme.Spacing.xl)
    }
}
