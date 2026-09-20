import Foundation

/// What `updateCommandMetadata` wrote for one command, plus the scheduler's bookkeeping for it.
struct ExtensionCommandMetadata: Codable, Sendable, Equatable {
    /// Set by `updateCommandMetadata`, cleared by `null`; nil falls back to the manifest subtitle.
    var subtitle: String?
    /// Off until the first manual run or the Settings toggle.
    var backgroundEnabled = false
    var lastRun: Date?
    var lastError: String?
    var consecutiveFailures = 0
    /// Off until the command runs once; its schedule then measures from the shared lastRun.
    var menuBarEnabled = false
    /// The last settled render, so a menu bar item comes back without executing the extension.
    var menuBarSnapshot: ExtensionMenuBarSnapshot?

    init() {}

    /// Each key decodes on its own, so a new field cannot take every command's row down with it.
    init(from decoder: Decoder) throws {
        let record = try decoder.container(keyedBy: CodingKeys.self)
        subtitle = try record.decodeIfPresent(String.self, forKey: .subtitle)
        backgroundEnabled = try record.decodeIfPresent(Bool.self, forKey: .backgroundEnabled) ?? false
        lastRun = try record.decodeIfPresent(Date.self, forKey: .lastRun)
        lastError = try record.decodeIfPresent(String.self, forKey: .lastError)
        consecutiveFailures = try record.decodeIfPresent(Int.self, forKey: .consecutiveFailures) ?? 0
        menuBarEnabled = try record.decodeIfPresent(Bool.self, forKey: .menuBarEnabled) ?? false
        menuBarSnapshot = try record.decodeIfPresent(
            ExtensionMenuBarSnapshot.self, forKey: .menuBarSnapshot)
    }
}
