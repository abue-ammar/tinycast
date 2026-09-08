import Foundation

/// What `updateCommandMetadata` wrote for one command, plus the scheduler's bookkeeping for it.
struct ExtensionCommandMetadata: Codable, Sendable, Equatable {
    /// Set by `updateCommandMetadata`, cleared by `null`; nil falls back to the manifest subtitle.
    var subtitle: String?
    /// Off until the first manual run or the Settings toggle, exactly as in Raycast.
    var backgroundEnabled = false
    var lastRun: Date?
    var lastError: String?
    var consecutiveFailures = 0
}
