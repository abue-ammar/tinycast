import AppKit

@main
@MainActor
struct UninstallCoordinatorTests {
    static func main() async {
        for confirmed in [false, true] {
            for quitSucceeded in [false, true] {
                AppLauncher.quitSucceeded = quitSucceeded
                AppLauncher.quitRequests = []
                UninstallRunner.moved = []
                let session = UninstallSession()
                let core = AppCore()
                core.confirmed = confirmed
                let coordinator = UninstallCoordinator(
                    session: session, palette: PaletteState(), paletteCoordinator: PaletteCoordinator(),
                    appIndex: AppIndex(), runningApps: RunningAppsMonitor(), hotKeys: HotKeyManager(),
                    favorites: FavoritesStore(), visibility: VisibilityStore(),
                    ranking: LauncherRankingStore(),
                    aliases: AliasStore(), core: core)

                coordinator.performUninstall()
                let deadline = ContinuousClock.now + .seconds(5)
                while !core.finished, ContinuousClock.now < deadline {
                    try? await Task.sleep(for: .milliseconds(1))
                }
                expect(core.finished, "the operation completes")
                expect(
                    AppLauncher.quitRequests.count == (confirmed ? 1 : 0),
                    "confirmation rechecks the app even when the scan and monitor say it is stopped")
                if let request = AppLauncher.quitRequests.first {
                    expect(request.0 == session.app?.bundleID, "quit uses the selected bundle ID")
                    expect(request.1 == session.app?.url, "quit uses the selected installation")
                }
                expect(
                    UninstallRunner.moved == (confirmed && quitSucceeded ? session.selectedCandidates : []),
                    "only a confirmed uninstall whose quit succeeds reaches the runner")
                expect(
                    core.notices == (confirmed && !quitSucceeded ? ["Nothing Was Moved"] : []),
                    "a refused quit explains why no files moved")
                expect(!session.isTrashing, "success, refusal and cancellation release the busy state")
            }
        }
        print("ALL PASSED")
    }

    private static func expect(_ condition: Bool, _ message: String) {
        guard condition else {
            print("FAIL: \(message)")
            exit(1)
        }
    }
}

// Platform effects are recorded so the shipped coordinator cannot touch installed apps or files.
struct AppEntry {
    enum Kind { case application }
    let id = "fixture"
    let name = "Fixture"
    let url = URL(fileURLWithPath: "/Applications/Fixture.app")
    let bundleID: String? = "com.tinycast.uninstall-fixture"
    let kind = Kind.application
    var preferenceKey: String { id }
    var hotKeyAction: String? { nil }
}

@MainActor
final class UninstallSession {
    let app: AppEntry? = AppEntry()
    let plan: UninstallPlan? = UninstallPlan(
        target: UninstallTarget(
            bundleURL: AppEntry().url, bundleID: AppEntry().bundleID,
            displayName: "Fixture", bundleName: nil),
        candidates: [], isTargetRunning: false)
    var isTrashing = false
    var canConfirm: Bool { !isTrashing }
    let selectedCandidates = [
        UninstallCandidate(
            path: "/Applications/Fixture.app", name: "Fixture", locationLabel: "/Applications",
            evidence: .bundle, isDirectory: true, size: .zero, protection: .removable)
    ]

    func begin(app: AppEntry, otherAppNames: [String], otherBundleIDs: [String], isRunning: Bool) {}
    func setTrashing(_ value: Bool) { isTrashing = value }
}

@MainActor
enum AppLauncher {
    static var quitSucceeded = true
    static var quitRequests: [(String, URL)] = []

    static func quitAwaitingExit(bundleID: String, url: URL) async -> Bool {
        quitRequests.append((bundleID, url))
        await Task.yield()
        return quitSucceeded
    }

    static func showInFinder(_ url: URL) {}
    static func showInfoInFinder(_ url: URL) async -> Bool { true }
}

@MainActor
enum UninstallRunner {
    static var moved: [UninstallCandidate] = []

    static func moveToTrash(_ candidates: [UninstallCandidate]) async -> UninstallReport {
        moved = candidates
        return UninstallReport()
    }
}

struct UninstallReport {
    let hasFailures = false
    let removedBundle = false
    let trashedCount = 1
    let freedBytes: Int64 = 0
    let failed: [UninstallFailedItem] = []
}

struct UninstallFailedItem {
    let name: String
    let reason: String
}

@MainActor
final class AppCore {
    enum Tone { case danger }
    var confirmed = true
    var finished = false
    var notices: [String] = []

    func confirm(title: String, message: String, symbol: String, confirmTitle: String) async -> Bool {
        await Task.yield()
        if !confirmed { finished = true }
        return confirmed
    }

    func showNotice(title: String, message: String, symbol: String, tone: Tone) async {
        notices.append(title)
        finished = true
    }

    func showMessage(_ message: String) { finished = true }
}

struct PaletteState {
    enum Mode { case launcher, uninstall }
    func pop() -> Bool { true }
    func prepare(mode: Mode) {}
}

struct PaletteCoordinator {
    func navigate(to mode: PaletteState.Mode) {}
    func hidePalette(restoreFocus: Bool) {}
}

struct AppIndex {
    let apps: [AppEntry] = []
    func refresh() async {}
}

struct RunningAppsMonitor {
    func isRunning(_ app: AppEntry) -> Bool { false }
}

final class HotKeyManager {
    var recordingAction: String?
    func setBinding(_ binding: String?, for action: String) {}
}

struct FavoritesStore {
    func remove(keys: [String]) {}
}

struct VisibilityStore {
    func removeItemKeys(_ keys: [String]) {}
}

struct LauncherRankingStore {
    func reset(itemKey: String) {}
}

struct AliasStore {
    func removeKeys(_ keys: [String]) {}
}

enum Paster {
    static func copyPlainText(_ text: String) {}
}
