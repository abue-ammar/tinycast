import AppKit
import CloudKit
import Security

enum CloudSyncAvailability {
    /// A build without the entitlement crashes on its first `CKContainer`, so this asks first.
    static var isEntitled: Bool {
        (entitlement("com.apple.developer.icloud-services") as? [String])?.contains("CloudKit") == true
    }

    static var container: CKContainer {
        CKContainer(identifier: "iCloud." + (Bundle.main.bundleIdentifier ?? "com.abueammar.tinycast"))
    }

    static func unavailability(of container: CKContainer) async -> CloudSyncUnavailability? {
        do {
            switch try await container.accountStatus() {
            case .available: return nil
            case .restricted: return .restricted
            case .temporarilyUnavailable, .couldNotDetermine: return .temporarilyUnavailable
            case .noAccount: return .noAccount
            @unknown default: return .temporarilyUnavailable
            }
        } catch {
            return .temporarilyUnavailable
        }
    }

    /// Pushes make another Mac's change arrive within seconds rather than at the next poll.
    @MainActor
    static func registerForPushes() {
        guard entitlement("com.apple.developer.aps-environment") is String else { return }
        NSApplication.shared.registerForRemoteNotifications()
    }

    private static func entitlement(_ name: String) -> Any? {
        guard let task = SecTaskCreateFromSelf(nil) else { return nil }
        return SecTaskCopyValueForEntitlement(task, name as CFString, nil)
    }
}
