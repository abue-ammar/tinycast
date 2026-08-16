import Foundation

struct NoteID: RawRepresentable, Hashable, Sendable {
    let rawValue: String
}

struct NoteSummary: Identifiable, Sendable, Equatable {
    let id: NoteID
    let title: String
    let modifiedAt: Date
}

struct NoteSearchResult: Identifiable, Sendable, Equatable {
    var id: NoteID { summary.id }
    let summary: NoteSummary
    let score: Int
}

struct NoteDocument: Sendable, Equatable {
    let id: NoteID
    let source: String
}

struct NoteEditorInput: Sendable, Equatable {
    let id: NoteID
    let source: String
    let epoch: Int
}
