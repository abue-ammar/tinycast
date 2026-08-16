import Foundation

struct NoteSwitcherRenameState: Sendable, Equatable {
    private(set) var id: NoteID?
    private(set) var draft = ""

    var isActive: Bool { id != nil }

    mutating func begin(id: NoteID, title: String) {
        self.id = id
        draft = title
    }

    mutating func updateDraft(_ updated: String) {
        guard isActive else { return }
        draft = updated
    }

    mutating func cancel() {
        id = nil
        draft = ""
    }

    mutating func commit() -> (id: NoteID, title: String)? {
        guard let id else { return nil }
        let committed = (id, draft)
        cancel()
        return committed
    }
}

enum NoteSwitcherSelection {
    static func replacement(
        afterRemoving removed: NoteID,
        from orderedIDs: [NoteID],
        fallback: NoteID?
    ) -> NoteID? {
        guard let removedIndex = orderedIDs.firstIndex(of: removed) else { return fallback }
        let remaining = orderedIDs.filter { $0 != removed }
        if remaining.indices.contains(removedIndex) { return remaining[removedIndex] }
        return remaining.last ?? fallback
    }
}
