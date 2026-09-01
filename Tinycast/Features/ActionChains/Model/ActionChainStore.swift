import Foundation

enum ActionChainValidationError: LocalizedError {
    case emptyName
    case emptySteps
    case duplicateName

    var errorDescription: String? {
        switch self {
        case .emptyName: return "Enter a name for the action chain."
        case .emptySteps: return "Add at least one action."
        case .duplicateName: return "An action chain with this name already exists."
        }
    }
}

@MainActor
@Observable
final class ActionChainStore {
    private static let defaultsKey = "actionChains"

    private let defaults: UserDefaults
    private(set) var chains: [ActionChain]
    @ObservationIgnored var onChange: (([ActionChain]) -> Void)?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        chains =
            defaults.data(forKey: Self.defaultsKey)
            .flatMap { try? JSONDecoder().decode([ActionChain].self, from: $0) } ?? []
    }

    func chain(id: UUID) -> ActionChain? { chains.first { $0.id == id } }

    @discardableResult
    func add(_ draft: ActionChain) throws -> ActionChain {
        let value = try validated(draft)
        commit(chains + [value])
        return value
    }

    func update(_ draft: ActionChain) throws {
        guard let index = chains.firstIndex(where: { $0.id == draft.id }) else { return }
        var updated = chains
        updated[index] = try validated(draft)
        commit(updated)
    }

    func remove(id: UUID) {
        guard let index = chains.firstIndex(where: { $0.id == id }) else { return }
        var updated = chains
        updated.remove(at: index)
        commit(updated)
    }

    @discardableResult
    func replace(with incoming: [ActionChain]) -> Int {
        var accepted: [ActionChain] = []
        for chain in incoming {
            guard let value = try? validated(chain, among: accepted) else { continue }
            accepted.append(value)
        }
        commit(accepted)
        return accepted.count
    }

    private func validated(_ draft: ActionChain) throws -> ActionChain {
        try validated(draft, among: chains)
    }

    private func validated(_ draft: ActionChain, among existing: [ActionChain]) throws -> ActionChain {
        var value = draft
        value.name = value.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.name.isEmpty else { throw ActionChainValidationError.emptyName }
        guard !value.steps.isEmpty else { throw ActionChainValidationError.emptySteps }
        guard
            !existing.contains(where: {
                $0.id != value.id && $0.name.localizedCaseInsensitiveCompare(value.name) == .orderedSame
            })
        else { throw ActionChainValidationError.duplicateName }
        return value
    }

    private func commit(_ updated: [ActionChain]) {
        chains = updated.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        defaults.set(try? JSONEncoder().encode(chains), forKey: Self.defaultsKey)
        onChange?(chains)
    }
}
