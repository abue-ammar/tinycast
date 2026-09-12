import Foundation

/// The layout library. Authored data, so a bad record is cleaned rather than discarded.
@MainActor
@Observable
final class WindowLayoutStore {
    private static let defaultsKey = "windowLayouts"

    private let defaults: UserDefaults
    private(set) var layouts: [WindowLayout]
    @ObservationIgnored var onChange: (([WindowLayout]) -> Void)?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let decoded =
            defaults.data(forKey: Self.defaultsKey)
            .flatMap { try? JSONDecoder().decode([WindowLayout].self, from: $0) } ?? []
        layouts = Self.sanitized(decoded)
        if layouts != decoded { persist() }
    }

    func layout(id: UUID) -> WindowLayout? {
        layouts.first { $0.id == id }
    }

    func layout(entryID: String) -> WindowLayout? {
        WindowLayout.id(fromEntryID: entryID).flatMap(layout)
    }

    // Takes a whole draft, so adding a field doesn't churn every call site.
    @discardableResult
    func add(_ draft: WindowLayout) throws(WindowLayoutValidationError) -> WindowLayout {
        let value = try validated(draft)
        commit(layouts + [value])
        return value
    }

    func update(_ draft: WindowLayout) throws(WindowLayoutValidationError) {
        guard let index = layouts.firstIndex(where: { $0.id == draft.id }) else { return }
        let value = try validated(draft)
        var updated = layouts
        updated[index] = value
        commit(updated)
    }

    /// A copy takes a new identity throughout, so it can't inherit the original's shortcut.
    @discardableResult
    func duplicate(id: UUID) throws(WindowLayoutValidationError) -> WindowLayout? {
        guard let original = layout(id: id) else { return nil }
        let copy = WindowLayout(
            name: Self.uniqueName(from: original.name, among: layouts),
            iconSymbol: original.iconSymbol, usesPreferredGap: original.usesPreferredGap,
            entries: original.entries.map(\.copy))
        return try add(copy)
    }

    @discardableResult
    func remove(id: UUID) -> WindowLayout? {
        guard let index = layouts.firstIndex(where: { $0.id == id }) else { return nil }
        var updated = layouts
        let removed = updated.remove(at: index)
        commit(updated)
        return removed
    }

    /// Replaces the whole library on backup import, cleaning rather than rejecting.
    @discardableResult
    func replace(with incoming: [WindowLayout]) -> Int {
        let updated = Self.sanitized(incoming)
        commit(updated)
        return updated.count
    }

    private func validated(
        _ draft: WindowLayout
    ) throws(WindowLayoutValidationError) -> WindowLayout {
        var value = draft
        value.name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        value.iconSymbol = draft.iconSymbol?.trimmingCharacters(in: .whitespacesAndNewlines)
        value.entries = WindowLayoutEntry.sanitized(draft.entries)
        guard !value.name.isEmpty else { throw .emptyName }
        guard !value.name.contains("\0") else { throw .invalidCharacter }
        guard !value.entries.isEmpty else { throw .noEntries }
        guard
            !layouts.contains(where: {
                $0.id != value.id
                    && $0.name.compare(value.name, options: .caseInsensitive) == .orderedSame
            })
        else { throw .duplicateName }
        return value
    }

    private func commit(_ updated: [WindowLayout]) {
        let ordered = updated.sorted(by: WindowLayout.precedes)
        guard ordered != layouts else { return }
        layouts = ordered
        persist()
        onChange?(ordered)
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(layouts) else { return }
        defaults.set(data, forKey: Self.defaultsKey)
    }

    /// "Office" → "Office Copy" → "Office Copy 2", so a duplicate never fails validation.
    private static func uniqueName(from name: String, among existing: [WindowLayout]) -> String {
        let taken = Set(existing.map { $0.name.lowercased() })
        let base = name + " Copy"
        guard taken.contains(base.lowercased()) else { return base }
        var index = 2
        while taken.contains("\(base) \(index)".lowercased()) { index += 1 }
        return "\(base) \(index)"
    }

    private static func sanitized(_ values: [WindowLayout]) -> [WindowLayout] {
        var ids = Set<UUID>()
        var names = Set<String>()
        var result: [WindowLayout] = []
        for value in values {
            // Copy-and-clean rather than rebuild, so a new field can never be dropped on import.
            var cleaned = value
            cleaned.name = value.name.trimmingCharacters(in: .whitespacesAndNewlines)
            cleaned.iconSymbol = value.iconSymbol?.trimmingCharacters(in: .whitespacesAndNewlines)
            cleaned.entries = WindowLayoutEntry.sanitized(value.entries)
            let foldedName = cleaned.name.folding(options: [.caseInsensitive], locale: .current)
            guard !cleaned.name.isEmpty, !cleaned.name.contains("\0"), !cleaned.entries.isEmpty,
                ids.insert(cleaned.id).inserted, names.insert(foldedName).inserted
            else { continue }
            result.append(cleaned)
        }
        return result.sorted(by: WindowLayout.precedes)
    }
}
