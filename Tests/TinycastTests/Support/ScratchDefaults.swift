import Foundation
import Testing

/// A preferences domain of the test's own, removed with its plist when the test lets go of it.
final class ScratchDefaults {
    let defaults: UserDefaults
    private let name: String

    init(_ label: String = "defaults") throws {
        name = "tinycast-tests-\(label)-\(UUID().uuidString)"
        defaults = try #require(UserDefaults(suiteName: name))
    }

    deinit {
        defaults.removePersistentDomain(forName: name)
        CFPreferencesAppSynchronize(name as CFString)
        // cfprefsd leaves the emptied domain's plist behind.
        try? FileManager.default.removeItem(
            at: FileManager.default.homeDirectoryForCurrentUser
                .appending(path: "Library/Preferences/\(name).plist"))
    }
}
