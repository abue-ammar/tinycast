import CloudKit
import Foundation
import OSLog

@MainActor
final class CloudSyncStateStore {
    struct State: Codable, Sendable {
        var engine: CKSyncEngine.State.Serialization?
        var ledger = SyncLedger()
        var deviceID = UUID().uuidString
        var deviceName: String?
        /// The other Macs as last fetched; the engine never fetches a record twice.
        var devices: [String: SyncDevice] = [:]
        /// What this build syncs; a change re-fetches everything older builds skipped.
        var catalog: String?
        var deferred: [String: Deferred] = [:]
    }

    struct Deferred: Codable, Sendable {
        let key: String
        let isDeletion: Bool
    }

    /// A deferred arrival: a payload, or nil for a deletion.
    struct Arrival {
        let key: String
        let payload: Data?
    }

    private nonisolated static let logger = Logger(subsystem: "com.tinycast", category: "CloudSync")
    private static let saveDelay: Duration = .seconds(1)

    private(set) var state: State
    private let directory: URL
    private var saveTask: Task<Void, Never>?

    init(
        directory: URL = AppPaths.applicationSupport().appending(
            path: "CloudSync", directoryHint: .isDirectory)
    ) {
        self.directory = directory
        let data = try? Data(contentsOf: directory.appending(path: "state.json"))
        state = data.flatMap { try? JSONDecoder().decode(State.self, from: $0) } ?? State()
    }

    func update(_ change: (inout State) -> Void) {
        change(&state)
        scheduleSave()
    }

    /// Forgets everything sync knew, keeping only this Mac's identity.
    func reset() {
        let identity = (state.deviceID, state.deviceName)
        state = State()
        (state.deviceID, state.deviceName) = identity
        try? FileManager.default.removeItem(at: deferredDirectory)
        scheduleSave()
    }

    func flush() {
        guard saveTask != nil else { return }
        saveTask?.cancel()
        saveTask = nil
        Self.write(state, to: directory)
    }

    // MARK: Deferred arrivals

    func clearDeferred(in category: SyncCategory) {
        let names = state.deferred.compactMap { name, entry in
            SyncSourceID(recordName: name)?.category(of: entry.key) == category ? name : nil
        }
        clearDeferred(names)
    }

    func deferArrival(_ name: String, key: String, payload: Data?) {
        if let payload {
            try? FileManager.default.createDirectory(at: deferredDirectory, withIntermediateDirectories: true)
            try? payload.write(to: deferredDirectory.appending(path: name), options: [.atomic])
        }
        update { $0.deferred[name] = Deferred(key: key, isDeletion: payload == nil) }
    }

    func hasDeferred(of source: SyncSourceID) -> Bool {
        state.deferred.keys.contains { SyncSourceID(recordName: $0) == source }
    }

    func deferredArrivals(of source: SyncSourceID) -> [String: Arrival] {
        var arrivals: [String: Arrival] = [:]
        for (name, deferred) in state.deferred where SyncSourceID(recordName: name) == source {
            let payload =
                deferred.isDeletion ? nil : try? Data(contentsOf: deferredDirectory.appending(path: name))
            guard deferred.isDeletion || payload != nil else { continue }
            arrivals[name] = Arrival(key: deferred.key, payload: payload)
        }
        return arrivals
    }

    func clearDeferred(_ names: some Collection<String>) {
        guard !names.isEmpty else { return }
        for name in names { try? FileManager.default.removeItem(at: deferredDirectory.appending(path: name)) }
        update { state in for name in names { state.deferred[name] = nil } }
    }

    // MARK: Writing

    private var deferredDirectory: URL { directory.appending(path: "Deferred", directoryHint: .isDirectory) }

    private func scheduleSave() {
        guard saveTask == nil else { return }
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: Self.saveDelay)
            guard !Task.isCancelled, let self else { return }
            saveTask = nil
            await Self.writeOffMain(state, to: directory)
        }
    }

    @concurrent
    private static func writeOffMain(_ state: State, to directory: URL) async {
        write(state, to: directory)
    }

    private nonisolated static func write(_ state: State, to directory: URL) {
        do {
            try FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700])
            let url = directory.appending(path: "state.json")
            try JSONEncoder().encode(state).write(to: url, options: [.atomic])
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        } catch {
            logger.error("Saving sync state failed: \(String(describing: error), privacy: .public)")
        }
    }
}
