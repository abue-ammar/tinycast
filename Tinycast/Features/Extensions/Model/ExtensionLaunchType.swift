import Foundation

/// Mirrors `@raycast/api` `LaunchType`; the raw values must match `LaunchType` in
/// `Scripts/raycast-runtime/src/api/enums.generated.js`, which is what JS compares against.
enum ExtensionLaunchType: String, Sendable {
    case userInitiated
    case background
}
