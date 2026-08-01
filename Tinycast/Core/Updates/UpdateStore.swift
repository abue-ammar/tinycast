import Foundation
import Sparkle

/// Owns the app's one `SPUUpdater` and republishes it as something SwiftUI can render. Sparkle's own
/// windows never appear: `UpdateUserDriver` implements `SPUUserDriver` in full, so every confirmation
/// is a Tinycast dialog.
///
/// Checking the feed reaches the network, so the *background* cadence is gated on explicit consent and
/// ships off. The flag is Sparkle's own `SUEnableAutomaticChecks` user default rather than a second
/// one of ours, and deliberately not part of `AppSettings`: `SettingsBackup` mirrors that type
/// field-for-field, and an imported config must never be able to grant network access.
@MainActor
final class UpdateStore: NSObject, ObservableObject, SPUUpdaterDelegate {
    enum State: Equatable {
        case idle
        case checking
        /// Fraction complete, nil while the download's length is unknown or implausible.
        case downloading(Double?)
        case extracting
        case readyToRelaunch
        case failed(String)
    }

    /// Named in the consent sheet.
    static let provider = "GitHub Pages"
    static let providerURL = URL(string: "https://abue-ammar.github.io/tinycast/")!
    static let releasesURL = URL(string: "https://github.com/abue-ammar/tinycast/releases")!

    /// One feed per channel, never `sparkle:channel`: Sparkle always allows the default channel, so a
    /// beta host would still be offered the stable DMG, whose app name and bundle id match neither and
    /// whose install is then rejected. A bundle id absent from this table has no feed at all, which is
    /// what makes the dev channel provably un-updatable rather than merely unconfigured.
    private nonisolated static let feeds = [
        "com.tinycast.app": URL(string: "https://abue-ammar.github.io/tinycast/appcast.xml")!,
        "com.tinycast.app.beta": URL(string: "https://abue-ammar.github.io/tinycast/appcast-beta.xml")!
    ]

    /// Nonisolated so the launcher's `CommandRegistry`, which is built off the main actor, can drop
    /// the update command on a channel that has no feed without reaching into main-actor state.
    nonisolated static func feedURL(for bundleID: String?) -> URL? {
        guard let bundleID else { return nil }
        return feeds[bundleID]
    }

    /// Sparkle's own activity defaults, cleared when consent is withdrawn.
    private static let activityKeys = ["SULastCheckTime", "SUSkippedVersion"]
    /// Sparkle nests its downloads one level below the app's own cache directory. Removing the
    /// *parent* would take `CurrencyRateStore`'s snapshot with it.
    private static let cacheComponent = "org.sparkle-project.Sparkle"

    /// Consent for background checks. Sparkle's default is the setting; this only republishes it.
    /// Absent reads as false, which is the only safe default for a network feature.
    @Published private(set) var isEnabled = false
    @Published private(set) var state: State = .idle
    @Published private(set) var lastCheckDate: Date?

    private let defaults = UserDefaults.standard
    private lazy var driver = UpdateUserDriver(store: self)
    /// Lazy because `SPUUpdater` takes both its user driver and its delegate at init, and both are
    /// rooted in `self`, which doesn't exist yet in a stored-property initializer.
    private lazy var updater = SPUUpdater(
        hostBundle: .main, applicationBundle: .main, userDriver: driver, delegate: self)

    private var feed: URL? { Self.feedURL(for: Bundle.main.bundleIdentifier) }

    /// False on the dev channel, which has no feed — hide or disable every update affordance.
    var isSupported: Bool { feed != nil }

    /// "0.7.5 (128)" — the same shape `AboutView` renders.
    var currentVersion: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
        return "\(short) (\(build))"
    }

    /// From `AppCore.start()`. Guard 1 — an unsupported channel never even builds an updater, so
    /// `start()` can be called unconditionally. With `SUEnableAutomaticChecks = NO` this performs zero
    /// network I/O: Sparkle early-returns before arming its timer.
    func start() {
        guard isSupported else { return }
        do {
            try updater.start()
        } catch {
            state = .failed(error.localizedDescription)
            return
        }
        isEnabled = updater.automaticallyChecksForUpdates
        lastCheckDate = updater.lastUpdateCheckDate
    }

    /// The Settings toggle's only entry point, called after the user accepts the consent dialog.
    /// Disabling must leave nothing behind: Sparkle's activity defaults and its download cache go too.
    /// Guard 2 — a channel with no feed has nothing to consent to.
    func setEnabled(_ enabled: Bool) {
        guard isSupported, enabled != isEnabled else { return }
        updater.automaticallyChecksForUpdates = enabled
        // Sparkle owns the flag, so read it back rather than assume the write took.
        isEnabled = updater.automaticallyChecksForUpdates
        guard !enabled else { return }
        state = .idle
        lastCheckDate = nil
        for key in Self.activityKeys { defaults.removeObject(forKey: key) }
        try? FileManager.default.removeItem(at: cacheDirectory)
    }

    /// The explicit gesture, from the menu bar or the palette. Always allowed — consent gates the
    /// unattended cadence, not a check the user just asked for. Guard 3 — no feed, no check;
    /// `canCheckForUpdates` additionally covers a failed `start()` and a session already in flight.
    func checkNow() {
        guard isSupported, updater.canCheckForUpdates else { return }
        driver.isUserInitiated = true
        state = .checking
        updater.checkForUpdates()
    }

    /// `UpdateUserDriver`'s only channel back, so the store stays the single thing SwiftUI observes.
    func publish(_ state: State) {
        self.state = state
        lastCheckDate = updater.lastUpdateCheckDate
    }

    private var cacheDirectory: URL {
        let bundleID = Bundle.main.bundleIdentifier ?? "com.tinycast.app"
        return FileManager.default
            .urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(bundleID, isDirectory: true)
            .appendingPathComponent(Self.cacheComponent, isDirectory: true)
    }

    // MARK: - SPUUpdaterDelegate

    /// The feed is supplied here rather than by `SUFeedURL`, which is absent from `Info.plist` on
    /// purpose: the delegate wins over the plist, and returning nil leaves no URL to fall back to.
    func feedURLString(for _: SPUUpdater) -> String? { feed?.absoluteString }

    /// Belt and braces. `SUEnableAutomaticChecks` in `Info.plist` already suppresses Sparkle's own
    /// permission prompt permanently; Tinycast's consent sheet is the only thing allowed to ask.
    func updaterShouldPromptForPermissionToCheck(forUpdates _: SPUUpdater) -> Bool { false }
}
