import Foundation

/// RAII handle for a block-based `NotificationCenter` observation (dropping the token removes the observer), owned here so the thread-safe `removeObserver` runs from a nonisolated `deinit` a `@MainActor` class couldn't reach under Swift 6.
final class NotificationToken {
    private let center: NotificationCenter
    private let token: any NSObjectProtocol

    init(_ token: any NSObjectProtocol, center: NotificationCenter) {
        self.token = token
        self.center = center
    }

    deinit {
        center.removeObserver(token)
    }
}
