import Foundation

/// One headless refresh, from launch to outcome. The outcome is buffered rather than signalled, so a
/// command that finishes before anyone waits still reports what it did.
@MainActor
final class ExtensionBackgroundSession {
    enum Outcome: Sendable, Equatable {
        case success
        case failure(String)
        /// Preempted or torn down: the schedule is left exactly as the run found it.
        case cancelled

        var error: String? {
            if case .failure(let message) = self { return message }
            return nil
        }
    }

    let id = UUID().uuidString
    let reference: ExtensionCommandRef
    private(set) var outcome: Outcome?
    private let outcomes: AsyncStream<Outcome>
    private let continuation: AsyncStream<Outcome>.Continuation

    init(reference: ExtensionCommandRef) {
        self.reference = reference
        (outcomes, continuation) = AsyncStream.makeStream(bufferingPolicy: .bufferingNewest(1))
    }

    /// First one wins: a late delegate callback cannot overwrite a timeout or an abort.
    func complete(_ outcome: Outcome) {
        guard self.outcome == nil else { return }
        self.outcome = outcome
        continuation.yield(outcome)
        continuation.finish()
    }

    func wait(timeout: TimeInterval) async -> Outcome {
        if let outcome { return outcome }
        let outcomes = self.outcomes
        let settled = await withTaskGroup(of: Outcome.self) { group in
            group.addTask {
                for await outcome in outcomes { return outcome }
                return .cancelled
            }
            group.addTask {
                do { try await Task.sleep(for: .seconds(timeout)) } catch { return .cancelled }
                return .failure("Timed out.")
            }
            defer { group.cancelAll() }
            return await group.next() ?? .cancelled
        }
        complete(settled)
        return outcome ?? settled
    }
}
