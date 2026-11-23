import AppKit
import CloudKit
import OSLog

/// iCloud Sync's action surface and lifecycle: one session while the switch is on, none while off.
@MainActor
@Observable
final class CloudSyncCoordinator {
    struct Counts: Codable, Equatable, Sendable {
        let local: Int
        let cloud: Int
    }

    private static let logger = Logger(subsystem: "com.tinycast", category: "CloudSync")
    private static let changeDelay: Duration = .seconds(1)
    private static let refreshInterval: Duration = .seconds(15 * 60)

    private(set) var status: CloudSyncStatus = .off
    private(set) var counts: [SyncCategory: Counts] = [:]
    /// Why sync last turned itself off, until the switch is used again.
    private(set) var stopReason: CloudSyncStopReason?

    @ObservationIgnored private unowned let core: AppCore
    @ObservationIgnored private let store = CloudSyncStateStore()
    @ObservationIgnored private(set) lazy var devices = DeviceSyncSource(store: store)
    @ObservationIgnored private lazy var sources: [any SyncSource] = makeSources()
    @ObservationIgnored private var session: CloudSyncSession?
    @ObservationIgnored private var startTask: Task<Void, Never>?
    @ObservationIgnored private var syncTask: Task<Void, Never>?
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var pendingSources: Set<SyncSourceID> = []
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var isReady = false
    @ObservationIgnored private var wakeObserver: NotificationToken?
    @ObservationIgnored private var accountObserver: NotificationToken?

    init(core: AppCore) {
        self.core = core
    }

    var isEnabled: Bool { core.settings.iCloudSyncEnabled }

    func syncs(_ category: SyncCategory) -> Bool {
        isEnabled && includes(category)
    }

    func includes(_ category: SyncCategory) -> Bool {
        guard category.isOptional else { return true }
        return category.isOptIn
            ? core.settings.iCloudSyncOptedInCategories.contains(category)
            : !core.settings.iCloudSyncDisabledCategories.contains(category)
    }

    var syncsClipboard: Bool {
        syncs(.clipboardText) || syncs(.clipboardImages)
    }

    // MARK: Lifecycle

    /// Starts after the first app scan, so launcher records have entries to match.
    func appIndexDidScan() {
        guard !isReady else { return }
        isReady = true
        applyEnabled()
    }

    func applyEnabled() {
        guard isReady else { return }
        if isEnabled { start() } else { stop(forgetting: true) }
    }

    func setEnabled(_ enabled: Bool) {
        stopReason = nil
        core.settings.iCloudSyncEnabled = enabled
    }

    func setIncluded(_ included: Bool, for category: SyncCategory) {
        guard category.isOptional, included != includes(category) else { return }
        let settings = core.settings
        if included {
            if category.isOptIn {
                settings.iCloudSyncOptedInCategories.insert(category)
            } else {
                settings.iCloudSyncDisabledCategories.remove(category)
            }
            guard let session else { return }
            Task { await session.join() }
        } else {
            if category.isOptIn {
                settings.iCloudSyncOptedInCategories.remove(category)
            } else {
                settings.iCloudSyncDisabledCategories.insert(category)
            }
            store.clearDeferred(in: category)
            store.update { $0.ledger.forget(category) }
            refreshCounts()
        }
    }

    func refresh() {
        guard let session else { return applyEnabled() }
        Task { await session.fetch() }
    }

    func flush() {
        store.flush()
    }

    // MARK: Macs

    var otherDevices: [SyncDevice] {
        devices.others.values.sorted { $0.lastSeen > $1.lastSeen }
    }

    func renameThisMac(_ name: String) {
        devices.rename(to: name)
    }

    func removeDevice(_ id: String) {
        session?.delete(.device, key: id)
        devices.forget(id)
    }

    /// Deletes everything in iCloud; each Mac keeps its own data and turns sync off.
    func deleteCloudData() async {
        guard let session else { return }
        do {
            try await session.deleteAllData()
            setEnabled(false)
        } catch {
            core.showMessage(
                String(localized: "Couldn't delete the iCloud data. Try again later."), tone: .danger)
        }
    }

    // MARK: Session

    private func start() {
        guard session == nil, startTask == nil else { return }
        guard CloudSyncAvailability.isEntitled else {
            Self.logger.notice("Sync is unavailable: this build has no iCloud entitlement")
            status = .unavailable(.unsignedBuild)
            return
        }
        status = .syncing(initial: store.state.ledger.isEmpty)
        observeAccount()
        let container = CloudSyncAvailability.container
        startTask = Task { [weak self] in
            let unavailability = await CloudSyncAvailability.unavailability(of: container)
            guard let self else { return }
            startTask = nil
            guard isEnabled, session == nil else { return }
            if let unavailability {
                Self.logger.notice("Sync is waiting for iCloud: \(String(describing: unavailability))")
                status = .unavailable(unavailability)
                return
            }
            Self.logger.notice("Sync is starting")
            CloudSyncAvailability.registerForPushes()
            let session = CloudSyncSession(
                container: container, store: store, sources: sources,
                isEnabled: { [weak self] in self?.includes($0) ?? false },
                onEvent: { [weak self] in self?.handle($0) })
            self.session = session
            generation &+= 1
            for source in sources { observe(source, generation: generation) }
            observeFolders(generation: generation)
            observeWake()
            startRefreshing()
            forgetRebuiltClipboard()
            await session.start()
            refreshCounts()
        }
    }

    /// `forgetting` drops the ledger, so turning sync back on merges again instead of deleting.
    private func stop(forgetting: Bool) {
        generation &+= 1
        startTask?.cancel()
        startTask = nil
        syncTask?.cancel()
        syncTask = nil
        refreshTask?.cancel()
        refreshTask = nil
        pendingSources = []
        wakeObserver = nil
        if forgetting { accountObserver = nil }
        let retiring = session
        session = nil
        Task { await retiring?.stop() }
        if forgetting {
            store.reset()
            devices.reset()
            counts = [:]
            status = .off
        }
    }

    private func handle(_ event: CloudSyncSession.Event) {
        switch event {
        case .status(let newStatus):
            status = newStatus
            if newStatus == .needsUpdate { stop(forgetting: false) }
        case .ledgerChanged:
            refreshCounts()
        case .stopped(let reason):
            core.showMessage(reason.message, tone: .neutral)
            stopReason = reason
            core.settings.iCloudSyncEnabled = false
        case .restartNeeded:
            stop(forgetting: true)
            start()
        }
    }

    private func refreshCounts() {
        let ledger = store.state.ledger
        counts = Dictionary(
            uniqueKeysWithValues: SyncCategory.allCases.filter(\.isCounted).map { category in
                let counts = ledger.counts(of: category)
                return (category, Counts(local: counts.local, cloud: counts.cloud))
            })
    }

    // MARK: Watching

    /// One-shot and fired before the write lands, so the re-read and re-arm wait for a task.
    private func observe(_ source: any SyncSource, generation: Int) {
        withObservationTracking {
            source.observe()
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, generation == self.generation else { return }
                observe(source, generation: generation)
                schedule(source.id)
            }
        }
    }

    /// A new folder or a rebuilt clipboard is a different set of items, so it merges, never deletes.
    private func observeFolders(generation: Int) {
        let folders = (core.settings.notesFolder, core.settings.snippetsFolder)
        withObservationTracking {
            _ = core.settings.notesFolder
            _ = core.settings.snippetsFolder
            _ = core.clipboardStore.wasRebuilt
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, generation == self.generation, let session else { return }
                observeFolders(generation: generation)
                let notesMoved = folders.0 != self.core.settings.notesFolder
                let snippetsMoved = folders.1 != self.core.settings.snippetsFolder
                let rebuilt = forgetRebuiltClipboard()
                guard notesMoved || snippetsMoved || rebuilt else { return }
                store.update { state in
                    if notesMoved { state.ledger.forget(.notes) }
                    if snippetsMoved { state.ledger.forget(.snippets) }
                }
                await session.join()
            }
        }
    }

    @discardableResult
    private func forgetRebuiltClipboard() -> Bool {
        guard core.clipboardStore.wasRebuilt else { return false }
        core.clipboardStore.wasRebuilt = false
        store.update { state in
            state.ledger.forget(.clipboardText)
            state.ledger.forget(.clipboardImages)
        }
        return true
    }

    private func schedule(_ id: SyncSourceID) {
        pendingSources.insert(id)
        guard syncTask == nil else { return }
        syncTask = Task { [weak self] in
            try? await Task.sleep(for: Self.changeDelay)
            guard let self, !Task.isCancelled else { return }
            let ids = pendingSources
            pendingSources = []
            syncTask = nil
            for id in SyncSourceID.allCases where ids.contains(id) { await session?.sync(id) }
        }
    }

    /// Pushes can be late on macOS, so a slow poll and a wake from sleep catch what they miss.
    private func startRefreshing() {
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.refreshInterval)
                guard !Task.isCancelled, let session = self?.session else { return }
                await session.syncAll()
                await session.fetch()
            }
        }
    }

    private func observeWake() {
        let center = NSWorkspace.shared.notificationCenter
        let wake = NSWorkspace.didWakeNotification
        let token = center.addObserver(forName: wake, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        wakeObserver = NotificationToken(token, center: center)
    }

    /// A sign-in after "no account" starts sync; the engine itself reports later changes.
    private func observeAccount() {
        guard accountObserver == nil else { return }
        let center = NotificationCenter.default
        let changed = Notification.Name.CKAccountChanged
        let token = center.addObserver(forName: changed, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.isEnabled, self.session == nil else { return }
                self.start()
            }
        }
        accountObserver = NotificationToken(token, center: center)
    }

    private func makeSources() -> [any SyncSource] {
        let core = core
        let entryKeys = {
            SyncEntryKey(
                snippetFolder: core.snippetsStore.snippetsDirectory,
                homeDirectory: FileManager.default.homeDirectoryForCurrentUser)
        }
        let aiIsOn = { core.settings.aiEnabled }
        let rows = {
            Set(core.appIndex.apps.map(\.id))
                .union(core.quicklinks.quicklinks.map(\.entryID))
                .union(core.snippetsStore.snippets.map(\.entryID))
                .union(core.extensions.installed.flatMap(\.commandEntryIDs))
        }
        return [
            devices,
            SettingsSyncSource(
                bindings: core.settingsBindings.bindings, commit: core.settingsBindings.commit,
                settings: core.settings),
            EntryShortcutSyncSource(
                aliases: core.aliases, hotKeys: core.hotKeys, rows: rows, entryKeys: entryKeys),
            LauncherListSyncSource(
                favorites: core.favorites, fallbacks: core.fallbacks, entryKeys: entryKeys),
            SnippetSyncSource(store: core.snippetsStore),
            NoteSyncSource(store: core.notesStore),
            QuicklinkSyncSource(store: core.quicklinks),
            ChatSyncSource(
                store: core.chatHistory, isActive: aiIsOn, answering: { core.aiChats.answeringIDs }),
            RecordSyncSource.chatPresets(core.chatPresets, isActive: aiIsOn),
            RecordSyncSource.customQuickActions(core.customQuickActions),
            RecordSyncSource.mcpServers(
                { core.mcpSettings.servers }, apply: { core.mcpCoordinator.applySynced($0) },
                remove: { id in (try? core.mcpCoordinator.remove(id)) != nil }),
            ExtensionSyncSource(manager: core.extensions),
            ClipboardSyncSource(.text, store: core.clipboardStore) { [unowned self] in
                core.settings.clipboardEnabled && includes(.clipboardText)
            },
            ClipboardSyncSource(.image, store: core.clipboardStore) { [unowned self] in
                core.settings.clipboardEnabled && includes(.clipboardImages)
            }
        ]
    }
}
