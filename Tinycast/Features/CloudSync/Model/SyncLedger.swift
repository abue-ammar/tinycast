import Foundation

/// What this Mac knows about every synced item: the source of truth for what still has to upload.
struct SyncLedger: Codable, Equatable, Sendable {
    enum Pending: String, Codable, Sendable {
        case save, delete
    }

    struct Entry: Codable, Equatable, Sendable {
        let source: SyncSourceID
        let key: String
        /// The local content's version; nil while this Mac doesn't hold the item.
        var version: String?
        /// When the content last changed anywhere, which is what last-write-wins compares.
        var modifiedAt: Date
        /// The server record's archived system fields; nil until the server has the item.
        var systemFields: Data?
        /// The change tag those fields carry, so a re-fetch of a version held here is skipped.
        var changeTag: String?
        var pending: Pending?
        /// The version in flight, so a save confirmed after a newer edit can't clear that edit.
        var sentVersion: String?

        var category: SyncCategory? { source.category(of: key) }
    }

    enum Incoming: Equatable, Sendable {
        /// The server's copy wins: apply it, then report the result through `didApply`.
        case apply
        /// This Mac's newer edit wins: upload it again over the server's copy.
        case keepLocal
        /// This Mac already holds that very version, as a full re-fetch brings back.
        case unchanged
    }

    enum Deletion: Equatable, Sendable {
        case apply(Entry)
        case keepLocal
        case ignore
    }

    private(set) var entries: [String: Entry] = [:]
    /// Categories whose full fetch finished here; only these upload what this Mac had first.
    private(set) var joined: Set<SyncCategory> = []

    var isEmpty: Bool { entries.isEmpty && joined.isEmpty }

    func entry(named name: String) -> Entry? { entries[name] }

    func isJoined(_ source: SyncSourceID, key: String) -> Bool {
        guard let category = source.category(of: key) else { return true }
        return joined.contains(category)
    }

    mutating func join(_ categories: Set<SyncCategory>) {
        joined.formUnion(categories)
    }

    /// Drops a category, so turning it back on merges again rather than deleting.
    mutating func forget(_ category: SyncCategory) {
        joined.remove(category)
        entries = entries.filter { $0.value.category != category }
    }

    mutating func record(
        _ snapshot: [String: String], of source: SyncSourceID, now: Date,
        includes: (String) -> Bool
    ) -> [String: Pending] {
        var changes: [String: Pending] = [:]
        for (key, version) in snapshot where includes(key) {
            let name = source.recordName(for: key)
            guard entries[name]?.version != version else { continue }
            var entry = entries[name] ?? Entry(source: source, key: key, modifiedAt: now)
            entry.version = version
            entry.modifiedAt = now
            entry.pending = .save
            entries[name] = entry
            changes[name] = .save
        }
        for (name, entry) in entries
        where entry.source == source && entry.version != nil && snapshot[entry.key] == nil
            && includes(entry.key)
        {
            guard entry.systemFields != nil else {
                entries[name] = nil
                continue
            }
            var deleted = entry
            deleted.version = nil
            deleted.modifiedAt = now
            deleted.pending = .delete
            entries[name] = deleted
            changes[name] = .delete
        }
        return changes
    }

    /// A server record arrived, fetched or returned by a failed save; ties go to the server.
    mutating func receive(
        _ name: String, source: SyncSourceID, key: String, modifiedAt: Date, changeTag: String?,
        systemFields: Data
    ) -> Incoming {
        var entry = entries[name] ?? Entry(source: source, key: key, modifiedAt: modifiedAt)
        if let changeTag, changeTag == entry.changeTag, entry.pending == nil, entry.version != nil {
            return .unchanged
        }
        entry.systemFields = systemFields
        entry.changeTag = changeTag
        if entry.pending != nil, entry.modifiedAt > modifiedAt {
            entries[name] = entry
            return .keepLocal
        }
        entry.modifiedAt = modifiedAt
        entry.pending = nil
        entry.sentVersion = nil
        entries[name] = entry
        return .apply
    }

    /// Records the source's own re-read after an apply, so the change never echoes back.
    mutating func didApply(_ name: String, localVersion: String?) {
        entries[name]?.version = localVersion
    }

    /// A record deleted elsewhere; an edit this Mac hasn't uploaded yet outlives the delete.
    mutating func receiveDeletion(_ name: String) -> Deletion {
        guard var entry = entries[name] else { return .ignore }
        if entry.pending == .save {
            entry.systemFields = nil
            entry.changeTag = nil
            entries[name] = entry
            return .keepLocal
        }
        entries[name] = nil
        return .apply(entry)
    }

    mutating func willSend(_ name: String) -> Entry? {
        guard var entry = entries[name], entry.pending != nil else { return nil }
        entry.sentVersion = entry.version
        entries[name] = entry
        return entry
    }

    mutating func didSave(_ name: String, systemFields: Data, changeTag: String?) {
        guard var entry = entries[name] else { return }
        entry.systemFields = systemFields
        entry.changeTag = changeTag
        if entry.pending == .save, entry.sentVersion == entry.version { entry.pending = nil }
        entry.sentVersion = nil
        entries[name] = entry
    }

    mutating func didDelete(_ name: String) {
        guard entries[name]?.pending == .delete else { return }
        entries[name] = nil
    }

    /// The server no longer has the record a save expected, so the next save creates it anew.
    mutating func didLoseRecord(_ name: String) {
        entries[name]?.systemFields = nil
        entries[name]?.changeTag = nil
        entries[name]?.sentVersion = nil
    }

    /// Queues a delete of a record this Mac never held, such as another Mac's device record.
    mutating func requestDelete(_ name: String, now: Date) -> Bool {
        guard var entry = entries[name], entry.systemFields != nil else { return false }
        entry.version = nil
        entry.modifiedAt = now
        entry.pending = .delete
        entries[name] = entry
        return true
    }

    var pendingChanges: [String: Pending] {
        entries.compactMapValues(\.pending)
    }

    func counts(of category: SyncCategory) -> (local: Int, cloud: Int) {
        entries.values.reduce(into: (local: 0, cloud: 0)) { counts, entry in
            guard entry.category == category else { return }
            if entry.version != nil { counts.local += 1 }
            if entry.systemFields != nil, entry.pending != .delete { counts.cloud += 1 }
        }
    }
}
