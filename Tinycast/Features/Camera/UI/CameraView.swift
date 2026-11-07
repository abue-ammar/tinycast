import SwiftUI

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
        .background(GlassEffectView())
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.dialog, style: .continuous))
    }

    private var isLive: Bool {
        if case .live = coordinator.feed { return true }
        return false
    }

    private var footer: some View {
        HStack(spacing: Theme.Spacing.md) {
            if isLive {
                CameraButton(
                    title: String(localized: "Mirror"),
                    emphasis: coordinator.mirrored ? .primary : .secondary
                ) {
                    coordinator.mirrored.toggle()
                }
                if coordinator.canSwitchCamera {
                    CameraButton(title: String(localized: "Switch Camera"), emphasis: .secondary) {
                        coordinator.switchCamera()
                    }
                }
            }
            Spacer(minLength: Theme.Spacing.md)
            CameraButton(title: String(localized: "Close"), keyCaps: ["esc"], emphasis: .secondary) {
                coordinator.close()
            }
            if isLive {
                CameraButton(title: String(localized: "Take Photo"), keyCaps: ["↵"]) {
                    coordinator.takePhoto()
                }
            }
        }
        .padding(Theme.Spacing.xl)
    }
}
