import Foundation
import UserNotifications

/// Manages macOS user notifications for AI chat responses.
@MainActor
final class AINotificationManager {
    static let shared = AINotificationManager()

    private let center = UNUserNotificationCenter.current()

    private init() {}

    /// Request notification permission from the user.
    func requestPermission() async -> Bool {
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound])
            return granted
        } catch {
            return false
        }
    }

    /// Send a notification when an AI response arrives.
    func notifyResponseReceived(preview: String) async {
        let content = UNMutableNotificationContent()
        content.title = "AI Response"
        content.body = preview
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )

        do {
            try await center.add(request)
        } catch {
            print("Failed to send notification: \(error)")
        }
    }

    /// Check if notifications are authorized.
    func checkAuthorization() async -> Bool {
        let settings = await center.notificationSettings()
        return settings.authorizationStatus == .authorized
    }
}
