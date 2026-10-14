import SwiftUI

/// The palette's camera body: a warm-up that dissolves into the live stage once the camera settles.
struct CameraView: View {
    let coordinator: CameraCoordinator
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            if let feed = coordinator.feed {
                CameraStage(feed: feed, mirrored: coordinator.mirrored)
                    .transition(
                        .opacity.combined(with: .scale(scale: Theme.CameraMotion.arrivalScale)))
            } else {
                CameraWarmUp()
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Edge to edge under the header and the floating bar; the panel's own corners clip it.
        .ignoresSafeArea()
        .animation(reduceMotion ? nil : Theme.CameraMotion.reveal, value: coordinator.feed == nil)
    }
}

/// What stands in for the stage while `startRunning` blocks, so the wait reads as progress.
private struct CameraWarmUp: View {
    @Environment(\.metrics) private var metrics
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: metrics.spacing.md) {
            Image(systemName: "web.camera")
                .font(.system(size: Theme.Size.dialogIcon, weight: .light))
                .symbolEffect(.pulse, options: .repeating, isActive: !reduceMotion)
            Text("Starting camera…")
                .font(metrics.typography.rowTrailing)
        }
        .foregroundStyle(Theme.Colors.textSecondary)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
