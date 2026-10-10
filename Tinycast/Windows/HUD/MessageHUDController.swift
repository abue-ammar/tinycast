import AppKit
import SwiftUI

/// The message pill, shared by every feature that reports a transient confirmation.
@MainActor
final class MessageHUDController {
    private let presenter: HUDPresenter
    private let settings: AppSettings

    init(settings: AppSettings) {
        self.settings = settings
        presenter = HUDPresenter(
            anchor: .edgeInset(Theme.Size.hudEdgeOffset),
            dwell: Theme.Duration.messageHUD,
            screen: { settings.openOnCursorScreen ? .underCursor : .primary })
    }

    func show(message: String, tone: DialogTone = .success) {
        let notice = Self.notice(in: message)
        presenter.show(
            MessageHUDView(message: notice, accessory: .tone(tone)).environment(\.metrics, metrics),
            dwell: Self.dwell(for: notice))
    }

    /// Two lines hold one paragraph; what follows it is for a surface with the room.
    static func notice(in message: String) -> String {
        message.components(separatedBy: "\n\n").first ?? message
    }

    /// A short confirmation keeps the usual beat; a two-line one stays long enough to be read.
    static func dwell(for message: String) -> TimeInterval {
        let reading = Double(message.count) / Theme.Duration.messageHUDReadingRate
        return min(max(Theme.Duration.messageHUD, reading), Theme.Duration.messageHUDLongest)
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
