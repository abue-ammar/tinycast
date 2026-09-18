import Foundation

/// The dictionary screen's lookup: one term in flight, answered off the main actor.
@MainActor
@Observable
final class DictionarySession {
    struct Lookup: Equatable {
        let term: String
        /// Nil when no enabled dictionary knows the term.
        let entry: DictionaryEntry?
    }

    /// The last answered lookup; it stays up while the next term resolves, so typing never blanks.
    private(set) var lookup: Lookup?
    @ObservationIgnored private var term = ""
    @ObservationIgnored private var task: Task<Void, Never>?

    /// Coalesces a burst of keystrokes into the lookup for the word they settle on.
    private static let debounce = Duration.milliseconds(90)

    func lookUp(_ query: String) {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard term != self.term else { return }
        self.term = term
        task?.cancel()
        guard !term.isEmpty else {
            lookup = nil
            return
        }
        task = Task { [weak self] in
            try? await Task.sleep(for: Self.debounce)
            guard !Task.isCancelled else { return }
            let entry = await Task.detached(priority: .userInitiated) {
                DictionaryService.entry(for: term)
            }.value
            guard !Task.isCancelled else { return }
            self?.lookup = Lookup(term: term, entry: entry)
        }
    }

    func reset() {
        task?.cancel()
        task = nil
        term = ""
        lookup = nil
    }
}
