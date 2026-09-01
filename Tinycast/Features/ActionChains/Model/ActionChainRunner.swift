import Foundation

enum ActionChainRunResult: Equatable, Sendable {
    case completed
    case failed(step: ActionChainStep)
}

/// Runs one chain serially and never starts a step after a failure.
@MainActor
enum ActionChainRunner {
    static func run(
        _ chain: ActionChain, perform: (ActionChainStep) async throws -> Void
    ) async -> ActionChainRunResult {
        for step in chain.steps {
            do {
                try await perform(step)
            } catch {
                return .failed(step: step)
            }
        }
        return .completed
    }
}
