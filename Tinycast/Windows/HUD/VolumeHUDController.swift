import AppKit
import SwiftUI

/// The volume readout; a box, not the pill, because a level needs a bar and a number.
@MainActor
final class VolumeHUDController {
    private let settings: AppSettings
    private let presenter = HUDPresenter(
        anchor: .heightFraction(bottomFraction), dwell: Theme.Duration.volumeHUD,
        screen: { .underCursor })
    private let state = VolumeState(level: 0)

    init(settings: AppSettings) {
        self.settings = settings
    }

    func show(level: Float32, muted: Bool) {
        // The view observes `state`, so a repeat animates the bar rather than replaying.
        let showing = presenter.isShowing
        state.level = VolumeLevel.clamped(Double(level))
        state.muted = muted
        if showing {
            presenter.extend()
        } else {
            let metrics = settings.interfaceSize.metrics
            presenter.show(
                VolumeHUDView(state: state).environment(\.metrics, metrics),
                size: CGSize(width: metrics.size.hudWidth, height: metrics.size.hudHeight))
        }
    }

    /// Higher than the pill, the box being taller, so their edge distance reads equal.
    private static let bottomFraction: CGFloat = 0.12
}
