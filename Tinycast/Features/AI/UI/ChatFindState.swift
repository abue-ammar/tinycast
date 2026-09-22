import Foundation
import Observation

/// Find in the open chat: what the toolbar's field holds, and which match of it is current.
@MainActor
@Observable
final class ChatFindState {
    var query = "" {
        didSet { if query != oldValue { current = 0 } }
    }
    private(set) var current = 0
    /// Per message, so a streaming flush searches only the reply that changed.
    @ObservationIgnored private var cache: [UUID: Cached] = [:]

    private typealias Cached = (needle: String, message: ChatMessage, found: [ChatFindOccurrence])

    var needle: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }
    var isSearching: Bool { !needle.isEmpty }

    /// Every match, word by word in reading order, not one stop per message.
    func occurrences(in messages: [ChatMessage]) -> [ChatFindOccurrence] {
        let needle = needle
        guard !needle.isEmpty else {
            cache = [:]
            return []
        }
        var next: [UUID: Cached] = [:]
        let found = messages.flatMap { message -> [ChatFindOccurrence] in
            if let hit = cache[message.id], hit.needle == needle, hit.message == message {
                next[message.id] = hit
                return hit.found
            }
            let found = ChatFindIndex.occurrences(of: needle, in: [message])
            next[message.id] = (needle, message, found)
            return found
        }
        cache = next
        return found
    }

    /// Wraps at both ends, as Find does everywhere else on the Mac.
    func step(_ delta: Int, in messages: [ChatMessage]) {
        let count = occurrences(in: messages).count
        guard count > 0 else { return }
        current = ((current + delta) % count + count) % count
    }

    func currentOccurrence(in occurrences: [ChatFindOccurrence]) -> ChatFindOccurrence? {
        occurrences.isEmpty ? nil : occurrences[min(current, occurrences.count - 1)]
    }
}
