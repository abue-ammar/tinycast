import Foundation

/// The custom-size library, as JSON in `UserDefaults`. Authored data, so a bad record is cleaned.
@MainActor
@Observable
final class CustomWindowSizeStore {
    private static let defaultsKey = "customWindowSizes"

    private let defaults: UserDefaults
    private(set) var sizes: [CustomWindowSize]
    @ObservationIgnored var onChange: (([CustomWindowSize]) -> Void)?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let decoded =
            defaults.data(forKey: Self.defaultsKey)
            .flatMap { try? JSONDecoder().decode([CustomWindowSize].self, from: $0) } ?? []
        sizes = Self.sanitized(decoded)
        if sizes != decoded { persist() }
    }

    func size(id: UUID) -> CustomWindowSize? {
        sizes.first { $0.id == id }
    }

    @discardableResult
    func add(
        _ draft: CustomWindowSize
    ) throws(CustomWindowSizeValidationError) -> CustomWindowSize {
        let value = try validated(draft)
        commit(sizes + [value])
        return value
    }

    func update(_ draft: CustomWindowSize) throws(CustomWindowSizeValidationError) {
        guard let index = sizes.firstIndex(where: { $0.id == draft.id }) else { return }
        let value = try validated(draft)
        var updated = sizes
        updated[index] = value
        commit(updated)
    }

    @discardableResult
    func remove(id: UUID) -> CustomWindowSize? {
        guard let index = sizes.firstIndex(where: { $0.id == id }) else { return nil }
        var updated = sizes
        let removed = updated.remove(at: index)
        commit(updated)
        return removed
    }

    /// Replaces the whole library on backup import, cleaning rather than rejecting.
    @discardableResult
    func replace(with incoming: [CustomWindowSize]) -> Int {
        let updated = Self.sanitized(incoming)
        commit(updated)
        return updated.count
    }

    private func validated(
        _ draft: CustomWindowSize
    ) throws(CustomWindowSizeValidationError) -> CustomWindowSize {
        let value = draft.sanitized
        guard !value.name.isEmpty else { throw .emptyName }
        guard !value.name.contains("\0") else { throw .invalidCharacter }
        guard
            !sizes.contains(where: {
                $0.id != value.id
                    && $0.name.compare(value.name, options: .caseInsensitive) == .orderedSame
            })
        else { throw .duplicateName }
        return value
    }

    private func commit(_ updated: [CustomWindowSize]) {
        let ordered = updated.sorted(by: CustomWindowSize.precedes)
        guard ordered != sizes else { return }
        sizes = ordered
        persist()
        onChange?(ordered)
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(sizes) else { return }
        defaults.set(data, forKey: Self.defaultsKey)
    }

    private static func sanitized(_ values: [CustomWindowSize]) -> [CustomWindowSize] {
        var ids = Set<UUID>()
        var names = Set<String>()
        var result: [CustomWindowSize] = []
        for value in values {
            let cleaned = value.sanitized
            // Unlocalized, so an import refuses exactly the names `validated` refuses.
            let foldedName = cleaned.name.folding(options: [.caseInsensitive], locale: nil)
            guard !cleaned.name.isEmpty, !cleaned.name.contains("\0"),
                ids.insert(cleaned.id).inserted, names.insert(foldedName).inserted
            else { continue }
            result.append(cleaned)
        }
        return result.sorted(by: CustomWindowSize.precedes)
    }
}
