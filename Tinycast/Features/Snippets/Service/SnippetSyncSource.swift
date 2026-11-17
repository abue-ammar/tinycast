import Foundation

/// Snippet files by file name; a deletion from another Mac goes to the Trash.
@MainActor
final class SnippetSyncSource: SyncSource {
    let id = SyncSourceID.snippets
    private let store: SnippetsStore

    init(store: SnippetsStore) {
        self.store = store
    }

    func observe() {
        _ = store.snippets
        _ = store.state
    }

    func snapshot() async -> [String: String]? {
        await store.syncedFiles()?.mapValues(SyncVersion.of)
    }

    func payload(for key: String) async -> Data? {
        guard SyncFileName.isValid(key) else { return nil }
        return await store.syncedFile(named: key)
    }

    func apply(_ changes: SyncChanges) async -> Set<String> {
        let files = changes.upserts.filter { SyncFileName.isValid($0.key) }
        let trashed = changes.deletions.filter(SyncFileName.isValid)
        guard !files.isEmpty || !trashed.isEmpty else { return [] }
        guard await store.applySynced(files, trashing: trashed) else { return Set(files.keys).union(trashed) }
        return []
    }

    func preserveLocal(_ key: String) async -> Bool {
        SyncFileName.isValid(key) ? await store.setAside(key) : false
    }
}
