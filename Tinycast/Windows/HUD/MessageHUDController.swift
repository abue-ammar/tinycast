import AppKit
import SwiftUI

@MainActor
final class MessageHUDController {
    private let presenter: HUDPresenter
    private let settings: AppSettings

    init(settings: AppSettings, presenter: HUDPresenter) {
        self.settings = settings
        self.presenter = presenter
    }

    func show(message: String, tone: DialogTone = .success) {
        presenter.show(
            MessageHUDView(message: message, accessory: .tone(tone)).environment(\.metrics, metrics))
    }

    /// Stays up until the work it reports ends and something replaces it, or `dismiss()` runs.
    func showProgress(message: String, onCancel: (() -> Void)? = nil) {
        presenter.show(
            MessageHUDView(message: message, accessory: .progress, onCancel: onCancel)
                .environment(\.metrics, metrics),
            dwells: false,
            interactive: onCancel != nil)
    }

    func dismiss() {
        presenter.dismiss()
    }

    private var metrics: InterfaceMetrics { settings.interfaceSize.metrics }
}
