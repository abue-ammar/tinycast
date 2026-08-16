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
    struct Revision: Sendable, Equatable {
        private let fingerprint: String

        init(data: Data) {
            var hash: UInt64 = 14_695_981_039_346_656_037
            for byte in data {
                hash ^= UInt64(byte)
                hash &*= 1_099_511_628_211
            }
            fingerprint = "\(data.count):\(String(hash, radix: 16))"
        }
    }

    let id: NoteID
    let source: String
    let revision: Revision
}

struct NoteEditorInput: Sendable, Equatable {
    let id: NoteID
    let source: String
    let epoch: Int
}
