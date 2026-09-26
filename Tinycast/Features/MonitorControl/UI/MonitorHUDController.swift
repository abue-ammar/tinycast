import AppKit
import SwiftUI

@MainActor
final class MonitorHUDController {
    @Observable
    final class State {
        var symbol = "sun.max.fill"
        var level = 0.0
        var label = ""
        var name = ""
    }

    private let state = State()
    private let settings: AppSettings
    private var displayID: UInt32?
    private lazy var presenter = HUDPresenter(
        anchor: .heightFraction(0.12), dwell: Theme.Duration.volumeHUD,
        screen: { [weak self] in
            NSScreen.screens.first {
                $0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32 == self?.displayID
            }
        })

    init(settings: AppSettings) { self.settings = settings }

    func show(display: MonitorKeyRouting.Display, control: MonitorControlKind,
              value: MonitorControlValue, pending: Bool = false) {
        let muted = display.values[.mute]?.current == 1
        let level = control == .mute ? display.values[.volume]?.fraction ?? 0 : value.fraction
        state.level = control != .brightness && muted ? 0 : level
        state.symbol = control == .brightness ? "sun.max.fill" : VolumeLevel.symbol(level: level, muted: muted)
        state.label = control != .brightness && muted ? "Muted" : VolumeLevel.percentage(level)
        present(display: display, pending: pending)
    }

    func showFailure(display: MonitorKeyRouting.Display) {
        state.level = 0
        state.symbol = "exclamationmark.display"
        state.label = "Unavailable"
        present(display: display)
    }

    func dismiss() { presenter.dismiss() }

    private func present(display: MonitorKeyRouting.Display, pending: Bool = false) {
        let sameDisplay = displayID == display.id
        displayID = display.id
        state.name = display.name
        if sameDisplay && presenter.isShowing {
            presenter.extend(dwells: !pending)
        } else {
            let metrics = settings.interfaceSize.metrics
            presenter.show(MonitorHUDView(state: state).environment(\.metrics, metrics),
                           size: CGSize(width: metrics.size.hudWidth, height: metrics.size.hudHeight), dwells: !pending)
        }
    }
}
