import AppKit
import Combine

/// Row order of the uninstall list, chosen from the header control.
enum UninstallSort: String, CaseIterable, Sendable {
    case path
    case size
    case name

    /// Header-control label ("Sort by Path").
    var title: String {
        switch self {
        case .path: return "Sort by Path"
        case .size: return "Sort by Size"
        case .name: return "Sort by Name"
        }
    }
    var systemImage: String {
        switch self {
        case .path: return "folder"
        case .size: return "externaldrive"
        case .name: return "textformat"
        }
    }
}

/// What a finished removal actually did — the screen reports this instead of the palette just closing.
struct UninstallOutcome: Equatable, Sendable {
    let removedCount: Int
    /// Bytes belonging to the paths that really went, so a partial failure can't overstate the total.
    let reclaimed: Int64
    let failures: [LeftoverItem]
    /// Trashed or unlinked — the summary has to name which, since only one of them is recoverable.
    let permanently: Bool
}

/// Where the uninstall screen is in its one-way flow. The palette stays open across all three, so the
/// user sees the removal happen and what it did rather than the window vanishing.
enum UninstallPhase: Equatable, Sendable {
    case selecting
    /// Carries which removal is running, so the progress line names it accurately.
    case removing(permanently: Bool)
    case done(UninstallOutcome)
}

/// State for the palette's uninstall screen: the app being removed, what would go to the Trash, and
/// which of those rows are checked. Owned by `AppCore` and reset on every `begin` — the screen is a
/// one-shot flow, so nothing here outlives the palette session that started it.
@MainActor
final class UninstallSession: ObservableObject {
    @Published private(set) var target: AppEntry?
    /// Every discovered path in the current sort order. `filtered(_:)` narrows this to what the list
    /// actually shows, which is what the palette's flat selection indexes.
    @Published private(set) var items: [LeftoverItem] = []
    @Published private(set) var sort: UninstallSort = .path
    @Published private(set) var isScanning = false
    /// Checked rows, keyed by `LeftoverItem.id`. Everything starts checked, as in Raycast.
    @Published private(set) var checked: Set<String> = []
    /// Drives which of the three screens renders; `.removing` also stops the footer firing twice.
    @Published private(set) var phase: UninstallPhase = .selecting

    /// Invalidates an in-flight scan whose results arrive after the user backed out or started another.
    private var scanToken = UUID()

    var checkedItems: [LeftoverItem] { items.filter { checked.contains($0.id) } }
    /// Rows the user may act on — the denominator of the header's count, since a locked row is never
    /// something they can select.
    var removableItems: [LeftoverItem] { items.filter(\.isRemovable) }
    var checkedSize: Int64 { checkedItems.reduce(0) { $0 + ($1.size ?? 0) } }
    func isChecked(_ item: LeftoverItem) -> Bool { checked.contains(item.id) }

    /// Rows matching the header's filter field — a plain case-insensitive substring over the file name
    /// and its path, so what the user types reads the way the placeholder promises. An empty query
    /// shows everything. Checked state is keyed by path, so filtering never disturbs it.
    func filtered(_ query: String) -> [LeftoverItem] {
        let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !needle.isEmpty else { return items }
        return items.filter {
            $0.url.lastPathComponent.lowercased().contains(needle)
                || $0.displayPath.lowercased().contains(needle)
        }
    }

    /// The row a flat selection index points at, filtered and clamped — the one place that rule lives, so
    /// the SwiftUI list and the AppKit key handler can't drift apart on it.
    func highlightedItem(selection: Int, query: String) -> LeftoverItem? {
        let visible = filtered(query)
        guard !visible.isEmpty else { return nil }
        return visible[min(max(selection, 0), visible.count - 1)]
    }

    func setSort(_ sort: UninstallSort) {
        guard sort != self.sort else { return }
        self.sort = sort
        items = Self.sorted(items, by: sort)
    }

    /// Path order puts the bundle first for free (`/Applications` sorts above `/Users`); size is
    /// largest-first, which is the order someone reclaiming disk space is reading for.
    private static func sorted(_ items: [LeftoverItem], by sort: UninstallSort) -> [LeftoverItem] {
        switch sort {
        case .path:
            return items.sorted {
                $0.url.path.localizedStandardCompare($1.url.path) == .orderedAscending
            }
        case .name:
            return items.sorted {
                $0.url.lastPathComponent.localizedStandardCompare($1.url.lastPathComponent)
                    == .orderedAscending
            }
        case .size:
            // Unmeasurable paths sort last rather than as zero, so a failed size reads as unknown.
            return items.sorted { ($0.size ?? -1) > ($1.size ?? -1) }
        }
    }

    /// Starts a fresh scan for `app`, in two stages so the list is usable immediately.
    ///
    /// Discovery is a handful of `stat`s and lands at once. **Sizes are measured afterwards**, one path
    /// at a time, because a size is a full tree walk: cold, a 3.5 GB bundle measured 32s here (116ms
    /// warm), and making the whole screen wait on that would read as a hang. Rows therefore appear with
    /// no size and fill in as each measurement returns.
    func begin(app: AppEntry) {
        let token = UUID()
        scanToken = token
        target = app
        items = []
        checked = []
        phase = .selecting
        isScanning = true

        let name = app.name
        let bundleID = app.bundleID
        // Resolve the bundle: some apps are only symlinked into /Applications (a Homebrew cask points
        // at its Caskroom payload), and trashing the link alone would take the app out of the launcher
        // while leaving every byte of it installed.
        let url = app.url.resolvingSymlinksInPath()
        // …and take the link with it, so /Applications isn't left holding a dangling alias.
        let link = url == app.url ? nil : app.url
        // Resolved on the main actor: LaunchServices lookups aren't safe to move off it, and a
        // surviving install sharing this bundle id makes every id-keyed path ambiguous.
        let hasSibling = Self.hasSiblingInstall(
            bundleID: bundleID, excluding: [app.url, url])
        let home = FileManager.default.homeDirectoryForCurrentUser

        Task { [weak self] in
            let discovered = await Task.detached(priority: .userInitiated) { () -> [LeftoverItem] in
                func item(_ url: URL, _ kind: LeftoverItem.Kind) -> LeftoverItem {
                    let facts = AppLeftovers.facts(for: url)
                    return LeftoverItem(
                        url: url, kind: kind, size: nil,
                        isRemovable: facts.isRemovable, isDirectory: facts.isDirectory)
                }
                var found = [item(url, .bundle)]
                if let link { found.append(item(link, .bundle)) }
                let support = AppLeftovers.supportPaths(
                    appName: name, bundleID: bundleID, home: home,
                    siblingBundleExists: hasSibling)
                found += support.map { item($0, .support) }
                return found
            }.value
            guard let self, scanToken == token else { return }
            items = Self.sorted(discovered, by: sort)
            // Everything removable starts checked; locked rows never do.
            checked = Set(discovered.filter(\.isRemovable).map(\.id))
            isScanning = false
            await measureSizes(token: token)
        }
    }

    /// Fills in the row sizes once they are all measured. The walks run concurrently — they are
    /// independent tree reads, so the wait is the slowest one rather than their sum — and land in a single
    /// assignment: publishing per row would re-render the whole list once per leftover path found.
    private func measureSizes(token: UUID) async {
        let pending = items.filter { $0.size == nil }.map(\.url)
        guard !pending.isEmpty else { return }
        let sizes = await Task.detached(priority: .utility) { () -> [String: Int64] in
            await withTaskGroup(of: (String, Int64?).self) { group in
                for url in pending {
                    group.addTask { (url.path, AppLeftovers.size(of: url)) }
                }
                var measured: [String: Int64] = [:]
                for await (path, size) in group {
                    if let size { measured[path] = size }
                }
                return measured
            }
        }.value
        // The session may have been ended (or restarted for another app) mid-walk.
        guard scanToken == token else { return }
        var updated = items
        for index in updated.indices {
            guard let size = sizes[updated[index].url.path] else { continue }
            updated[index] = LeftoverItem(
                url: updated[index].url, kind: updated[index].kind, size: size,
                isRemovable: updated[index].isRemovable, isDirectory: updated[index].isDirectory)
        }
        // Only the size order depends on what just landed; re-applying any other sort would be a no-op.
        items = sort == .size ? Self.sorted(updated, by: .size) : updated
    }

    /// Drops the session (backing out of the screen), so a late scan result can't repopulate it.
    func end() {
        scanToken = UUID()
        target = nil
        items = []
        checked = []
        isScanning = false
        phase = .selecting
    }

    func toggle(_ item: LeftoverItem) {
        // A locked row is display-only: it exists so the user can see what stays behind and why.
        guard item.isRemovable else { return }
        if checked.contains(item.id) {
            checked.remove(item.id)
        } else {
            checked.insert(item.id)
        }
    }

    /// Removes `targets`, quitting the app first when its bundle is among them, and lands the screen on
    /// a summary of what happened. Returns the outcome so the caller can act on the failures too.
    ///
    /// The caller passes the set it approved rather than letting this re-read `checkedItems`, so what a
    /// confirmation counted is exactly what gets removed. `permanently` unlinks instead of trashing and
    /// is only ever reached from the Permanently Delete row, which confirms first (`AppCore`) — the ↵ /
    /// footer default stays the recoverable one.
    @discardableResult
    func remove(_ targets: [LeftoverItem], permanently: Bool = false) async -> UninstallOutcome {
        guard phase == .selecting else {
            return UninstallOutcome(
                removedCount: 0, reclaimed: 0, failures: [], permanently: permanently)
        }
        // Retires the scan token so an in-flight `measureSizes` walk exits at its next check: it must not
        // keep mutating rows (or re-sorting them) while the removal runs or the summary is up.
        scanToken = UUID()
        phase = .removing(permanently: permanently)

        // Only when the bundle itself is going: unchecking it to clear caches alone shouldn't force-quit
        // an app the user is still using.
        if targets.contains(where: { $0.kind == .bundle }), let bundleID = target?.bundleID {
            await Self.quitAndWait(bundleID: bundleID)
        }

        let paths = targets.map(\.url)
        let failedPaths = await Task.detached(priority: .userInitiated) {
            AppLeftovers.remove(paths, permanently: permanently)
        }.value

        let failures = targets.filter { failedPaths.contains($0.url.path) }
        let removed = targets.filter { !failedPaths.contains($0.url.path) }
        let outcome = UninstallOutcome(
            removedCount: removed.count,
            reclaimed: removed.reduce(0) { $0 + ($1.size ?? 0) },
            failures: failures,
            permanently: permanently)
        phase = .done(outcome)
        return outcome
    }

    /// Another registered install claiming the same bundle id (`Xcode.app` beside `Xcode-beta.app`).
    /// Every bundle-id-keyed support path would then be ambiguous, so discovery drops them all.
    private static func hasSiblingInstall(bundleID: String?, excluding urls: [URL]) -> Bool {
        guard let bundleID else { return false }
        // The target counts under both its own path and its symlink resolution, so a cask linked into
        // /Applications isn't mistaken for two installs.
        let own = Set(
            urls.flatMap { [$0.standardizedFileURL.path, $0.resolvingSymlinksInPath().path] })
        return NSWorkspace.shared.urlsForApplications(withBundleIdentifier: bundleID)
            .contains {
                !own.contains($0.standardizedFileURL.path)
                    && !own.contains($0.resolvingSymlinksInPath().path)
            }
    }

    /// Graceful terminate plus a bounded wait — trashing a bundle out from under a running process
    /// leaves a zombie, and `trashItem` can fail outright while the app holds its own files open.
    private static func quitAndWait(bundleID: String) async {
        guard AppLauncher.quit(bundleID: bundleID) else { return }
        for _ in 0..<30 {
            if NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty {
                return
            }
            try? await Task.sleep(for: .milliseconds(100))
        }
    }
}
