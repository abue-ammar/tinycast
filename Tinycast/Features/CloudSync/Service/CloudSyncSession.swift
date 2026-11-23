import CloudKit
import Foundation
import OSLog

/// One CKSyncEngine per account. A delegate callback never awaits `fetchChanges`/`sendChanges`.
@MainActor
final class CloudSyncSession: CKSyncEngineDelegate {
    enum Event {
        case status(CloudSyncStatus)
        case ledgerChanged
        /// Sync stops here and forgets what it knew; local data stays.
        case stopped(CloudSyncStopReason)
        /// The account or its encryption changed: start over with a clean ledger.
        case restartNeeded
    }

    private static let logger = Logger(subsystem: "com.tinycast", category: "CloudSync")

    /// Everything this build syncs; when it grows, older builds' skipped records are fetched again.
    static let catalog = SyncVersion.of(
        Data(
            (SyncSourceID.allCases.map(\.rawValue) + SyncSettingScope.syncedKeys).joined(separator: ",").utf8)
    )

    private let container: CKContainer
    private let store: CloudSyncStateStore
    private let sources: [SyncSourceID: any SyncSource]
    private let isEnabled: (SyncCategory) -> Bool
    private let onEvent: (Event) -> Void
    private let assetDirectory = AppPaths.caches().appending(path: "CloudSync", directoryHint: .isDirectory)
    private var engine: CKSyncEngine?
    private var applying: [SyncSourceID: SyncChanges] = [:]
    private var isJoining = false
    private var problem: CloudSyncProblem?
    private var lastSynced: Date?

    init(
        container: CKContainer, store: CloudSyncStateStore, sources: [any SyncSource],
        isEnabled: @escaping (SyncCategory) -> Bool, onEvent: @escaping (Event) -> Void
    ) {
        self.container = container
        self.store = store
        self.sources = Dictionary(uniqueKeysWithValues: sources.map { ($0.id, $0) })
        self.isEnabled = isEnabled
        self.onEvent = onEvent
    }

    // MARK: Lifecycle

    func start() async {
        if store.state.engine == nil || needsJoin {
            await join()
        } else {
            makeEngine()
            await syncAll()
        }
    }

    func stop() async {
        let retiring = engine
        engine = nil
        await retiring?.cancelOperations()
    }

    /// Fetches everything from the start, merging what this Mac has into what iCloud holds.
    func join() async {
        isJoining = true
        report(.syncing(initial: true))
        await engine?.cancelOperations()
        store.update { $0.engine = nil }
        makeEngine()
        guard let fresh = self.engine else { return }
        do {
            try await fresh.fetchChanges()
        } catch {
            guard fresh === self.engine else { return }
            isJoining = false
            fail(error)
            return
        }
        guard fresh === self.engine else { return }
        let enabled = Set(SyncCategory.allCases.filter(isEnabled))
        store.update { state in
            state.ledger.join(enabled)
            state.catalog = Self.catalog
        }
        isJoining = false
        await syncAll()
        settle()
    }

    /// Also finishes a join whose fetch failed, so this Mac's own items still get to upload.
    func fetch() async {
        guard let engine, !isJoining else { return }
        if needsJoin { return await join() }
        requeuePending()
        do {
            try await engine.fetchChanges()
            try await engine.sendChanges()
            problem = nil
            settle()
        } catch {
            fail(error)
        }
    }

    func syncAll() async {
        for id in SyncSourceID.allCases { await sync(id) }
    }

    func sync(_ id: SyncSourceID) async {
        guard let engine, let source = sources[id], applying[id] == nil else { return }
        await applyDeferred(of: source)
        guard let snapshot = await source.snapshot(), engine === self.engine, applying[id] == nil
        else { return }
        let ledger = store.state.ledger
        let deferred = store.state.deferred
        var changes: [String: SyncLedger.Pending] = [:]
        store.update { state in
            changes = state.ledger.record(
                snapshot, of: id, now: .now, isDeferred: { deferred[$0] != nil }
            ) { key in
                self.includes(id, key, ledger: ledger)
            }
        }
        for (name, pending) in changes { queue(name, pending) }
        if !changes.isEmpty { onEvent(.ledgerChanged) }
    }

    func delete(_ id: SyncSourceID, key: String) {
        let name = id.recordName(for: key)
        var queued = false
        store.update { queued = $0.ledger.requestDelete(name, now: .now) }
        if queued { queue(name, .delete) }
    }

    /// Deletes the whole zone, which every other Mac reads as "sync was reset".
    func deleteAllData() async throws {
        guard let engine else { return }
        engine.state.add(pendingDatabaseChanges: [.deleteZone(CloudSyncRecordCodec.zoneID)])
        try await engine.sendChanges()
    }

    /// Re-adds what the ledger still owes iCloud, which the engine drops after a hard failure.
    func requeuePending() {
        for (name, pending) in store.state.ledger.pendingChanges { queue(name, pending) }
    }

    // MARK: CKSyncEngineDelegate

    func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
        guard syncEngine === engine else { return }
        switch event {
        case .stateUpdate(let update):
            store.update { $0.engine = update.stateSerialization }
        case .accountChange(let change):
            if case .signIn = change.changeType { return }
            onEvent(.restartNeeded)
        case .fetchedDatabaseChanges(let changes):
            for deletion in changes.deletions where deletion.zoneID == CloudSyncRecordCodec.zoneID {
                onEvent(deletion.reason == .encryptedDataReset ? .restartNeeded : .stopped(.dataDeleted))
            }
        case .fetchedRecordZoneChanges(let changes):
            await receive(
                changes.modifications.map(\.record), deletions: changes.deletions.map(\.recordID.recordName))
        case .sentRecordZoneChanges(let sent):
            await handleSent(sent)
        case .sentDatabaseChanges(let sent):
            for failure in sent.failedZoneSaves { fail(failure.error) }
        case .willFetchChanges, .willSendChanges:
            problem = nil
            if !isJoining { report(.syncing(initial: false)) }
        case .didFetchChanges, .didSendChanges:
            if !isJoining { settle() }
        default:
            break
        }
    }

    func nextRecordZoneChangeBatch(
        _ context: CKSyncEngine.SendChangesContext, syncEngine: CKSyncEngine
    ) async -> CKSyncEngine.RecordZoneChangeBatch? {
        guard syncEngine === engine else { return nil }
        let pending = syncEngine.state.pendingRecordZoneChanges.filter { context.options.scope.contains($0) }
        return await CKSyncEngine.RecordZoneChangeBatch(pendingChanges: pending) { [weak self] id in
            await self?.record(for: id, engine: syncEngine)
        }
    }

    // MARK: Receiving

    private func receive(_ records: [CKRecord], deletions: [String]) async {
        var arrivals: [SyncSourceID: SyncChanges] = [:]
        var superseded: Set<String> = []
        for record in records {
            guard CloudSyncRecordCodec.schemaVersion(of: record) <= CloudSyncRecordCodec.schemaVersion else {
                return await pauseForUpdate()
            }
            guard let item = CloudSyncRecordCodec.item(from: record), accepts(item.source, item.key) else {
                continue
            }
            let name = record.recordID.recordName
            var outcome = SyncLedger.Incoming.apply
            store.update { state in
                outcome = state.ledger.receive(
                    name, source: item.source, key: item.key, modifiedAt: item.modifiedAt,
                    changeTag: record.recordChangeTag,
                    systemFields: CloudSyncRecordCodec.systemFields(of: record))
            }
            if outcome != .unchanged, store.state.deferred[name] != nil { superseded.insert(name) }
            switch outcome {
            case .apply: arrivals[item.source, default: SyncChanges()].upserts[item.key] = item.payload
            case .keepLocal: requeue(name)
            case .unchanged: break
            }
        }
        for name in deletions {
            guard let source = SyncSourceID(recordName: name) else { continue }
            if name == SyncSourceID.device.recordName(for: store.state.deviceID) {
                return onEvent(.stopped(.removedElsewhere))
            }
            var outcome = SyncLedger.Deletion.ignore
            store.update { outcome = $0.ledger.receiveDeletion(name) }
            if let deferred = store.state.deferred[name], outcome != .ignore || !deferred.isDeletion {
                superseded.insert(name)
            }
            switch outcome {
            case .apply(let entry):
                arrivals[source]?.upserts[entry.key] = nil
                if entry.version != nil || source == .device || applying[source]?.upserts[entry.key] != nil {
                    arrivals[source, default: SyncChanges()].deletions.insert(entry.key)
                }
            case .keepLocal: requeue(name)
            case .ignore: break
            }
        }
        store.clearDeferred(superseded)
        for (id, changes) in arrivals where !changes.isEmpty { await apply(changes, to: id) }
    }

    private func apply(_ arrivals: SyncChanges, to id: SyncSourceID) async {
        guard let source = sources[id] else { return }
        guard applying[id] == nil else { return deferArrivals(arrivals, of: id) }
        applying[id] = arrivals
        defer { applying[id] = nil }
        guard let local = await source.snapshot() else { return deferArrivals(arrivals, of: id) }
        await merge(arrivals, into: source, over: local)
    }

    /// Meeting an item it already holds, a Mac sets a differing copy aside and drops a duplicate.
    private func merge(
        _ arrivals: SyncChanges, into source: any SyncSource, over local: [String: String]
    ) async {
        let id = source.id
        var changes = arrivals
        let identical = Set(changes.upserts.filter { local[$0.key] == SyncVersion.of($0.value) }.keys)
        changes.upserts = changes.upserts.filter { !identical.contains($0.key) }
        let unrecorded = Set(
            local.keys.filter { store.state.ledger.entry(named: id.recordName(for: $0))?.version == nil })
        for key in changes.upserts.keys where unrecorded.contains(key) {
            _ = await source.preserveLocal(key)
        }
        let candidates = unrecorded.subtracting(arrivals.upserts.keys)
        if !candidates.isEmpty, !changes.upserts.isEmpty {
            changes.deletions.formUnion(await source.duplicates(of: changes.upserts, among: candidates))
        }
        let deferred = changes.isEmpty ? [] : await source.apply(changes)
        let reread = changes.isEmpty ? local : await source.snapshot()
        store.update { state in
            for key in identical {
                let name = id.recordName(for: key)
                if state.deferred[name] == nil { state.ledger.didApply(name, localVersion: local[key]) }
            }
            for key in changes.upserts.keys where !deferred.contains(key) {
                let name = id.recordName(for: key)
                if state.deferred[name] == nil { state.ledger.didApply(name, localVersion: reread?[key]) }
            }
        }
        deferArrivals(
            SyncChanges(
                upserts: changes.upserts.filter { deferred.contains($0.key) },
                deletions: arrivals.deletions.intersection(deferred)),
            of: id)
        onEvent(.ledgerChanged)
    }

    private func applyDeferred(of source: any SyncSource) async {
        let id = source.id
        guard store.hasDeferred(of: id), applying[id] == nil else { return }
        applying[id] = SyncChanges()
        defer { applying[id] = nil }
        guard let local = await source.snapshot() else { return }
        let arrivals = store.deferredArrivals(of: id)
        guard !arrivals.isEmpty else { return }
        store.clearDeferred(arrivals.keys)
        var changes = SyncChanges()
        for arrival in arrivals.values where accepts(id, arrival.key) {
            if let payload = arrival.payload {
                changes.upserts[arrival.key] = payload
            } else {
                changes.deletions.insert(arrival.key)
            }
        }
        guard !changes.isEmpty else { return }
        applying[id] = changes
        await merge(changes, into: source, over: local)
    }

    private func deferArrivals(_ changes: SyncChanges, of id: SyncSourceID) {
        for (key, payload) in changes.upserts where accepts(id, key) {
            let name = id.recordName(for: key)
            if store.state.deferred[name] == nil { store.deferArrival(name, key: key, payload: payload) }
        }
        for key in changes.deletions where accepts(id, key) {
            let name = id.recordName(for: key)
            if store.state.deferred[name] == nil { store.deferArrival(name, key: key, payload: nil) }
        }
    }

    private func pauseForUpdate() async {
        report(.needsUpdate)
        store.update { $0.engine = nil }
        await stop()
    }

    // MARK: Sending

    private func record(for id: CKRecord.ID, engine syncEngine: CKSyncEngine) async -> CKRecord? {
        let name = id.recordName
        var entry: SyncLedger.Entry?
        store.update { entry = $0.ledger.willSend(name) }
        guard
            let entry, entry.pending == .save, syncEngine === engine,
            let payload = await sources[entry.source]?.payload(for: entry.key),
            let record = try? CloudSyncRecordCodec.record(
                named: name, systemFields: entry.systemFields, key: entry.key, payload: payload,
                modifiedAt: entry.modifiedAt, assetDirectory: assetDirectory)
        else {
            syncEngine.state.remove(pendingRecordZoneChanges: [.saveRecord(id)])
            return nil
        }
        return record
    }

    private func handleSent(_ sent: CKSyncEngine.Event.SentRecordZoneChanges) async {
        store.update { state in
            for record in sent.savedRecords {
                state.ledger.didSave(
                    record.recordID.recordName, systemFields: CloudSyncRecordCodec.systemFields(of: record),
                    changeTag: record.recordChangeTag)
            }
            for id in sent.deletedRecordIDs { state.ledger.didDelete(id.recordName) }
            for (id, error) in sent.failedRecordDeletes where error.code == .unknownItem {
                state.ledger.didDelete(id.recordName)
            }
        }
        for record in sent.savedRecords {
            try? FileManager.default.removeItem(
                at: assetDirectory.appending(path: record.recordID.recordName))
        }
        for failure in sent.failedRecordSaves {
            let name = failure.record.recordID.recordName
            switch failure.error.code {
            case .serverRecordChanged:
                if let server = failure.error.serverRecord { await receive([server], deletions: []) }
            case .unknownItem:
                store.update { $0.ledger.didLoseRecord(name) }
                requeue(name)
            case .zoneNotFound:
                engine?.state.add(pendingDatabaseChanges: [
                    .saveZone(CKRecordZone(zoneID: CloudSyncRecordCodec.zoneID))
                ])
                requeue(name)
            case .networkFailure, .networkUnavailable, .zoneBusy, .serviceUnavailable, .requestRateLimited,
                .notAuthenticated, .accountTemporarilyUnavailable:
                fail(failure.error)
            default:
                if (failure.error.userInfo[CKErrorUserDidResetEncryptedDataKey] as? Bool) == true {
                    return onEvent(.restartNeeded)
                }
                fail(failure.error)
            }
        }
        if !sent.savedRecords.isEmpty || !sent.deletedRecordIDs.isEmpty { onEvent(.ledgerChanged) }
    }

    // MARK: Helpers

    private var needsJoin: Bool {
        store.state.catalog != Self.catalog
            || SyncCategory.allCases.contains { isEnabled($0) && !store.state.ledger.joined.contains($0) }
    }

    private func makeEngine() {
        var configuration = CKSyncEngine.Configuration(
            database: container.privateCloudDatabase, stateSerialization: store.state.engine, delegate: self)
        configuration.automaticallySync = true
        let engine = CKSyncEngine(configuration)
        if store.state.engine == nil {
            engine.state.add(pendingDatabaseChanges: [
                .saveZone(CKRecordZone(zoneID: CloudSyncRecordCodec.zoneID))
            ])
        }
        self.engine = engine
        requeuePending()
    }

    private func includes(_ id: SyncSourceID, _ key: String, ledger: SyncLedger) -> Bool {
        guard let category = id.category(of: key) else { return id == .device }
        return isEnabled(category) && ledger.isJoined(id, key: key)
    }

    /// What this Mac takes in: an unknown setting from a newer build stays in iCloud untouched.
    private func accepts(_ id: SyncSourceID, _ key: String) -> Bool {
        guard let category = id.category(of: key) else { return id == .device }
        return isEnabled(category)
    }

    private func queue(_ name: String, _ pending: SyncLedger.Pending) {
        guard let engine else { return }
        let id = CloudSyncRecordCodec.recordID(named: name)
        switch pending {
        case .save:
            engine.state.remove(pendingRecordZoneChanges: [.deleteRecord(id)])
            engine.state.add(pendingRecordZoneChanges: [.saveRecord(id)])
        case .delete:
            engine.state.remove(pendingRecordZoneChanges: [.saveRecord(id)])
            engine.state.add(pendingRecordZoneChanges: [.deleteRecord(id)])
        }
    }

    private func requeue(_ name: String) {
        guard let pending = store.state.ledger.entry(named: name)?.pending else { return }
        queue(name, pending)
    }

    private func settle() {
        guard problem == nil else { return }
        lastSynced = .now
        report(.upToDate(lastSynced))
    }

    private func fail(_ error: any Error) {
        Self.logger.error("Sync failed: \(String(describing: error), privacy: .public)")
        let problem = Self.problem(for: error)
        self.problem = problem
        report(.offline(problem, lastSynced: lastSynced))
    }

    private func report(_ status: CloudSyncStatus) {
        onEvent(.status(status))
    }

    private static func problem(for error: any Error) -> CloudSyncProblem {
        guard let error = error as? CKError else { return .other(error.localizedDescription) }
        switch error.code {
        case .networkFailure, .networkUnavailable, .serverResponseLost: return .network
        case .zoneBusy, .serviceUnavailable, .requestRateLimited: return .busy
        case .quotaExceeded: return .storageFull
        case .notAuthenticated, .accountTemporarilyUnavailable, .managedAccountRestricted:
            return .accountNeedsAttention
        default: return .other(error.localizedDescription)
        }
    }
}
