import Foundation

/// Raw values must match `LaunchType` in `Scripts/raycast-runtime/src/api/enums.generated.js`.
enum ExtensionLaunchType: String, Sendable {
    case userInitiated
    case background
}
