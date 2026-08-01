import Foundation
import Sparkle

/// Tinycast's `SPUUserDriver`. Sparkle drives all update UI through this protocol, so implementing it
/// in full is what keeps Sparkle's own AppKit windows off screen: a confirmation goes through
/// `AppCore.askConfirmation`, a report through `AppCore.showNotice`, like the rest of the app.
///
/// Everything else is *published*, not shown. The app is an accessory: a background check that found
/// an update must not steal focus from whatever the user is actually doing, so progress reaches the
/// Settings row through `UpdateStore` and nothing appears until there is a question to ask.
@MainActor
final class UpdateUserDriver: NSObject, SPUUserDriver {
    /// Set by `UpdateStore.checkNow()`. Sparkle reports "no update found" and errors identically for
    /// scheduled and explicit checks; only the explicit one has earned the right to put a dialog up.
    var isUserInitiated = false

    private weak var store: UpdateStore?
    private var expectedLength: UInt64 = 0
    private var receivedLength: UInt64 = 0

    init(store: UpdateStore) {
        self.store = store
        super.init()
    }

    /// Never reached — `SUEnableAutomaticChecks` in `Info.plist` suppresses this prompt for good — but
    /// the answer still has to be the safe one rather than a default-constructed yes.
    func show(_: SPUUpdatePermissionRequest) async -> SUUpdatePermissionResponse {
        SUUpdatePermissionResponse(automaticUpdateChecks: false, sendSystemProfile: false)
    }

    /// Cancellation is deliberately dropped: nothing in Tinycast's UI can cancel a check in flight,
    /// and holding a block no one calls is dead weight. Same for the download's cancellation below.
    func showUserInitiatedUpdateCheck(cancellation _: @escaping () -> Void) {
        store?.publish(.checking)
    }

    func showUpdateFound(with appcastItem: SUAppcastItem, state _: SPUUserUpdateState) async
        -> SPUUserUpdateChoice {
        let version = appcastItem.displayVersionString
        // An information-only update has no archive to install; replying `.install` is explicitly
        // unsupported, so say where the release lives and leave the installation alone.
        guard !appcastItem.isInformationOnlyUpdate else {
            await AppCore.shared.showNotice(
                title: "Tinycast \(version) Is Available",
                message: "This release has to be installed by hand, from "
                    + "\(UpdateStore.releasesURL.absoluteString).",
                kind: .info)
            return .dismiss
        }

        var message = "You're on \(store?.currentVersion ?? "an older version")."
        if let date = appcastItem.date {
            message += " \(version) was released \(date.formatted(date: .abbreviated, time: .omitted))."
        }
        let confirmed = await AppCore.shared.askConfirmation(
            title: "Update to Tinycast \(version)", message: message, confirmTitle: "Update",
            destructive: false)
        // A refused dialog — one is already on screen — comes back false, which is a dismissal and
        // never a hang: Sparkle gets its reply either way.
        return confirmed ? .install : .dismiss
    }

    /// Release notes are not rendered anywhere in Tinycast, so both hooks are deliberately inert.
    func showUpdateReleaseNotes(with _: SPUDownloadData) {}

    func showUpdateReleaseNotesFailedToDownloadWithError(_: any Error) {}

    func showUpdateNotFoundWithError(_ error: any Error, acknowledgement: @escaping () -> Void) {
        store?.publish(.idle)
        // A scheduled check that found nothing is a non-event; only the explicit gesture gets an answer.
        guard isUserInitiated else {
            acknowledgement()
            return
        }
        let message = (error as NSError).localizedRecoverySuggestion
            ?? "Tinycast \(store?.currentVersion ?? "") is the latest version."
        Task {
            await AppCore.shared.showNotice(
                title: "You're Up to Date", message: message, kind: .info)
            acknowledgement()
        }
    }

    func showUpdaterError(_ error: any Error, acknowledgement: @escaping () -> Void) {
        // Sparkle routes "no update found" through this method too when the cycle aborts. That is an
        // outcome, not a failure, and reporting it as one would contradict the notice just shown.
        guard !Self.isNoUpdate(error) else {
            store?.publish(.idle)
            acknowledgement()
            return
        }
        store?.publish(.failed(error.localizedDescription))
        guard isUserInitiated else {
            NSLog("Tinycast: background update check failed: %@", error.localizedDescription)
            acknowledgement()
            return
        }
        Task {
            await AppCore.shared.showNotice(
                title: "Update Failed", message: error.localizedDescription, kind: .error)
            acknowledgement()
        }
    }

    func showDownloadInitiated(cancellation _: @escaping () -> Void) {
        expectedLength = 0
        receivedLength = 0
        store?.publish(.downloading(nil))
    }

    func showDownloadDidReceiveExpectedContentLength(_ expectedContentLength: UInt64) {
        expectedLength = expectedContentLength
    }

    func showDownloadDidReceiveData(ofLength length: UInt64) {
        receivedLength += length
        // The feed's length is allowed to be absent or simply wrong, so an implausible one falls back
        // to indeterminate rather than driving a bar past its own end.
        let known = expectedLength > 0 && receivedLength <= expectedLength
        let fraction = known ? Double(receivedLength) / Double(expectedLength) : nil
        store?.publish(.downloading(fraction))
    }

    func showDownloadDidStartExtractingUpdate() {
        store?.publish(.extracting)
    }

    func showExtractionReceivedProgress(_: Double) {
        store?.publish(.extracting)
    }

    func showReadyToInstallAndRelaunch() async -> SPUUserUpdateChoice {
        store?.publish(.readyToRelaunch)
        let confirmed = await AppCore.shared.askConfirmation(
            title: "Update Ready",
            message: "Tinycast will relaunch to finish installing. Decline and it installs the next "
                + "time you quit.",
            confirmTitle: "Relaunch Now", destructive: false)
        return confirmed ? .install : .dismiss
    }

    /// `retryTerminatingApplication` is intentionally unused: Tinycast never delays or cancels its own
    /// termination, and the hook is only for a driver that has to ask again.
    func showInstallingUpdate(
        withApplicationTerminated _: Bool, retryTerminatingApplication _: @escaping () -> Void
    ) {
        // `State` has no installing case, and needs none — the app is already on its way out.
        store?.publish(.readyToRelaunch)
    }

    func showUpdateInstalledAndRelaunched(_: Bool, acknowledgement: @escaping () -> Void) {
        store?.publish(.idle)
        acknowledgement()
    }

    /// Nothing to raise: Tinycast's dialogs are `.modalPanel` level and ordered front regardless, so
    /// whatever is on screen is already above everything the palette itself puts up.
    func showUpdateInFocus() {}

    func dismissUpdateInstallation() {
        expectedLength = 0
        receivedLength = 0
        isUserInitiated = false
        // A failure survives the teardown: Sparkle dismisses immediately after reporting one, and
        // clearing it here would wipe the only thing the Settings row has left to show.
        if let state = store?.state, case .failed = state { return }
        store?.publish(.idle)
    }

    private static func isNoUpdate(_ error: any Error) -> Bool {
        let error = error as NSError
        return error.domain == SUSparkleErrorDomain
            && error.code == Int(SUError.noUpdateError.rawValue)
    }
}
