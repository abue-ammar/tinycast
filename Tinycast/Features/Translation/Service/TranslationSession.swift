import Foundation
import Observation

@MainActor
@Observable
final class TranslationSession {
    enum State: Equatable {
        case idle
        case waiting
        case translating
        case completed
        case failed(String)
    }

    private(set) var state: State = .idle
    private(set) var result: TranslationResult?
    private(set) var successfulRequest: TranslationRequest?
    private(set) var generation = 0
    private(set) var successfulGeneration: Int?

    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private let debounce: Duration
    @ObservationIgnored private let sleep: @MainActor (Duration) async throws -> Void

    init(
        debounce: Duration = .milliseconds(600),
        sleep: @escaping @MainActor (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) {
        self.debounce = debounce
        self.sleep = sleep
    }

    isolated deinit { task?.cancel() }

    func schedule(
        _ request: TranslationRequest,
        using operation: @escaping @MainActor (TranslationRequest) async throws -> TranslationResult
    ) {
        begin(request, waits: true, using: operation)
    }

    func retry(
        _ request: TranslationRequest,
        using operation: @escaping @MainActor (TranslationRequest) async throws -> TranslationResult
    ) {
        begin(request, waits: false, using: operation)
    }

    func cancel() {
        generation += 1
        task?.cancel()
        task = nil
        if state == .waiting || state == .translating { state = .idle }
    }

    func reset() {
        cancel()
        result = nil
        successfulRequest = nil
        successfulGeneration = nil
        state = .idle
    }

    private func begin(
        _ request: TranslationRequest, waits: Bool,
        using operation: @escaping @MainActor (TranslationRequest) async throws -> TranslationResult
    ) {
        reset()
        guard !request.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let mine = generation
        let sleep = sleep
        let debounce = debounce
        state = waits ? .waiting : .translating
        task = Task { [weak self] in
            defer {
                if !Task.isCancelled, self?.generation == mine { self?.task = nil }
            }
            do {
                try Task.checkCancellation()
                if waits { try await sleep(debounce) }
                try Task.checkCancellation()
                guard self?.generation == mine else { return }
                self?.state = .translating
                let result = try await operation(request)
                try Task.checkCancellation()
                guard let self, self.generation == mine else { return }
                self.result = result
                self.successfulRequest = request
                self.successfulGeneration = mine
                self.state = .completed
            } catch is CancellationError {
                guard !Task.isCancelled, self?.generation == mine else { return }
                self?.state = .idle
            } catch {
                guard !Task.isCancelled, self?.generation == mine else { return }
                self?.state = .failed(error.localizedDescription)
            }
        }
    }
}
