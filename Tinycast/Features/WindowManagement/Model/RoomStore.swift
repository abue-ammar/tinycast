import CoreGraphics
import Foundation

/// The room library. Authored data, so a bad record is cleaned rather than discarded.
@MainActor
@Observable
final class RoomStore {
    private static let defaultsKey = "windowRooms"

    private let defaults: UserDefaults
    private(set) var rooms: [Room]
    @ObservationIgnored var onChange: (([Room]) -> Void)?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let decoded =
            defaults.data(forKey: Self.defaultsKey)
            .flatMap { try? JSONDecoder().decode([Room].self, from: $0) } ?? []
        rooms = Self.sanitized(decoded)
        if rooms != decoded { persist() }
    }

    func room(id: UUID) -> Room? {
        rooms.first { $0.id == id }
    }

    func room(entryID: String) -> Room? {
        Room.id(fromEntryID: entryID).flatMap(room)
    }

    func room(named name: String) -> Room? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return rooms.first { $0.name.compare(trimmed, options: .caseInsensitive) == .orderedSame }
    }

    /// Window IDs other rooms hold, so a room missing a window takes a free one first.
    func claimedWindowIDs(excluding id: UUID?) -> Set<UInt32> {
        Set(rooms.filter { $0.id != id }.flatMap { $0.windows.compactMap(\.windowID) })
    }

    @discardableResult
    func add(_ draft: Room) throws(RoomValidationError) -> Room {
        let value = try validated(draft)
        commit(rooms + [value])
        return value
    }

    func update(_ draft: Room) throws(RoomValidationError) {
        guard let index = rooms.firstIndex(where: { $0.id == draft.id }) else { return }
        let value = try validated(draft)
        var updated = rooms
        updated[index] = value
        commit(updated)
    }

    @discardableResult
    func remove(id: UUID) -> Room? {
        guard let index = rooms.firstIndex(where: { $0.id == id }) else { return nil }
        var updated = rooms
        let removed = updated.remove(at: index)
        commit(updated)
        return removed
    }

    /// Replaces the whole library on backup import, cleaning rather than rejecting.
    @discardableResult
    func replace(with incoming: [Room]) -> Int {
        let updated = Self.sanitized(incoming)
        commit(updated)
        return updated.count
    }

    func setLayout(_ kind: RoomLayoutKind, for id: UUID, onDisplay uuid: String) {
        modify(id) { $0.layoutsByDisplay[uuid.lowercased()] = kind }
    }

    func markEntered(id: UUID, at date: Date) {
        modify(id) { $0.lastEnteredAt = date }
    }

    private func modify(_ id: UUID, _ change: (inout Room) -> Void) {
        guard let index = rooms.firstIndex(where: { $0.id == id }) else { return }
        var updated = rooms
        change(&updated[index])
        commit(updated)
    }

    private func validated(_ draft: Room) throws(RoomValidationError) -> Room {
        var value = draft
        value.name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        value.windows = Self.sanitized(draft.windows)
        guard !value.name.isEmpty else { throw .emptyName }
        guard !value.name.contains("\0") else { throw .invalidCharacter }
        guard !value.windows.isEmpty else { throw .noWindows }
        guard
            !rooms.contains(where: {
                $0.id != value.id
                    && $0.name.compare(value.name, options: .caseInsensitive) == .orderedSame
            })
        else { throw .duplicateName }
        return value
    }

    private func commit(_ updated: [Room]) {
        let ordered = updated.sorted(by: Room.precedes)
        guard ordered != rooms else { return }
        rooms = ordered
        persist()
        onChange?(ordered)
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(rooms) else { return }
        defaults.set(data, forKey: Self.defaultsKey)
    }

    private static func sanitized(_ values: [Room]) -> [Room] {
        var ids = Set<UUID>()
        var names = Set<String>()
        var result: [Room] = []
        for value in values {
            // Copy-and-clean rather than rebuild, so a new field can never be dropped on import.
            var cleaned = value
            cleaned.name = value.name.trimmingCharacters(in: .whitespacesAndNewlines)
            cleaned.windows = sanitized(value.windows)
            let foldedName = cleaned.name.folding(options: [.caseInsensitive], locale: .current)
            guard !cleaned.name.isEmpty, !cleaned.name.contains("\0"), !cleaned.windows.isEmpty,
                ids.insert(cleaned.id).inserted, names.insert(foldedName).inserted
            else { continue }
            result.append(cleaned)
        }
        return result.sorted(by: Room.precedes)
    }

    /// A window with no app is dropped; a bad frame or cell is reset rather than trusted.
    private static func sanitized(_ windows: [RoomWindow]) -> [RoomWindow] {
        windows.compactMap { window in
            var cleaned = window
            cleaned.bundleID = window.bundleID.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleaned.bundleID.isEmpty else { return nil }
            let frame = window.unitFrame
            let finite = [frame.minX, frame.minY, frame.width, frame.height].allSatisfy(\.isFinite)
            if !finite || frame.width <= 0 || frame.height <= 0 {
                cleaned.unitFrame = CGRect(x: 0, y: 0, width: 1, height: 1)
            }
            if let cell = window.cell, !RoomGrid.isValid([cell]) { cleaned.cell = nil }
            return cleaned
        }
    }
}
