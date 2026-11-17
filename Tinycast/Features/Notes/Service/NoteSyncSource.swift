import Foundation

/// Notes by file name; a note deleted on another Mac goes to the Trash here.
@MainActor
final class NoteSyncSource: SyncSource {
    let id = SyncSourceID.notes
    private let store: NotesStore

    init(store: NotesStore) {
        self.store = store
    }

    func observe() {
        _ = store.summaries
        _ = store.notesDirectory
    }

    func snapshot() async -> [String: String]? {
        guard let sources = await store.syncedSources() else { return nil }
        return Dictionary(
            uniqueKeysWithValues: sources.map { ($0.key.rawValue, SyncVersion.of(Data($0.value.utf8))) })
    }

    func payload(for key: String) async -> Data? {
        guard SyncFileName.isValid(key) else { return nil }
        return await store.syncedSource(of: NoteID(rawValue: key)).map { Data($0.utf8) }
    }

    func apply(_ changes: SyncChanges) async -> Set<String> {
        var sources: [NoteID: String] = [:]
        for (key, payload) in changes.upserts where SyncFileName.isValid(key) {
            sources[NoteID(rawValue: key)] = String(bytes: payload, encoding: .utf8)
        }
        let trashed = Set(changes.deletions.filter(SyncFileName.isValid).map { NoteID(rawValue: $0) })
        guard !sources.isEmpty || !trashed.isEmpty else { return [] }
        guard await store.applySynced(sources, trashing: trashed) else {
            return Set(changes.upserts.keys).union(changes.deletions)
        }
        return []
    }

    func preserveLocal(_ key: String) async -> Bool {
        SyncFileName.isValid(key) ? await store.setAside(NoteID(rawValue: key)) : false
    }
}
