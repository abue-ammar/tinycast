import Foundation

@MainActor
final class KeyboardRemapper {
    private struct Recovery: Codable {
        let bootSessionID: String
        let keyboards: [String: SavedMapping]
    }

    private struct SavedMapping: Codable {
        let original: [HIDKeyMapping]
        var installed: HIDKeyMapping
        var pending: HIDKeyMapping?

        func ownedMapping(in existing: [HIDKeyMapping]) -> HIDKeyMapping? {
            let current = existing.filter { $0.source == installed.source }
            if current == [installed] { return installed }
            if let pending, current == [pending] { return pending }
            return nil
        }
    }

    private enum Update {
        case unchanged, changed, failed
    }

    private(set) var mapping: HIDKeyMapping?
    private(set) var sawKarabinerConflict = false

    private let defaults: UserDefaults
    private let recoveryKey: String
    private let bootSessionID: String?
    private var savedMappings: [String: SavedMapping]
    private lazy var system: HIDEventSystem? = makeSystem()

    init(defaults: UserDefaults = .standard, recoveryKey: String = "hyperKeyKeyboardMappings") {
        self.defaults = defaults
        self.recoveryKey = recoveryKey
        bootSessionID = Self.currentBootSessionID()
        let recovery = defaults.data(forKey: recoveryKey).flatMap {
            try? JSONDecoder().decode(Recovery.self, from: $0)
        }
        savedMappings = recovery?.bootSessionID == bootSessionID ? recovery?.keyboards ?? [:] : [:]
    }

    var keyboards: [HIDEventSystem.Keyboard] { system?.keyboards ?? [] }

    var remappedKeyboardNames: [String] {
        guard let mapping, let system else { return [] }
        return system.keyboards.filter { system.keyMappings(of: $0).contains(mapping) }.map(\.name)
    }

    @discardableResult
    func apply(_ mapping: HIDKeyMapping?) -> Bool {
        self.mapping = mapping
        guard mapping != nil || !savedMappings.isEmpty else { return true }
        guard bootSessionID != nil else { return false }
        return reconcileAll().succeeded
    }

    func clearLeftovers() {
        guard mapping == nil, !savedMappings.isEmpty else { return }
        reconcileAll()
    }

    func repair() -> Bool {
        guard mapping != nil else { return false }
        let result = reconcileAll()
        return result.succeeded && result.changed
    }

    private func makeSystem() -> HIDEventSystem? {
        guard let system = HIDEventSystem() else { return nil }
        system.onKeyboardConnected = { [weak self, weak system] keyboard in
            guard let self, let system,
                mapping != nil || savedMappings[String(keyboard.registryID)] != nil
            else { return }
            update(keyboard, in: system)
        }
        system.watchConnections()
        return system
    }

    @discardableResult
    private func reconcileAll() -> (succeeded: Bool, changed: Bool) {
        guard let system else { return (false, false) }
        let keyboards = system.keyboards
        sawKarabinerConflict = false
        var failed = 0
        var changed = false
        for keyboard in keyboards {
            switch update(keyboard, in: system) {
            case .unchanged: break
            case .changed: changed = true
            case .failed: failed += 1
            }
        }
        // A keyboard that refuses is skipped, and one connected later is placed by hot plug.
        let succeeded = mapping == nil ? savedMappings.isEmpty : keyboards.isEmpty || failed < keyboards.count
        return (succeeded, changed)
    }

    @discardableResult
    private func update(_ keyboard: HIDEventSystem.Keyboard, in system: HIDEventSystem) -> Update {
        let id = String(keyboard.registryID)
        let existing = system.keyMappings(of: keyboard)
        let saved = savedMappings[id]
        let owned = saved?.ownedMapping(in: existing)
        guard let mapping else {
            guard let saved else { return .unchanged }
            guard let owned else {
                save(nil, for: id)
                return .unchanged
            }
            let restored = owned.restoring(saved.original, in: existing)
            guard system.setKeyMappings(restored, on: keyboard) else { return .failed }
            save(nil, for: id)
            return .changed
        }

        if HyperKeyConflictPolicy.isKarabinerVirtualKeyboard(named: keyboard.name),
            mapping.conflicts(
                with: owned.map { $0.restoring(saved?.original ?? [], in: existing) } ?? existing)
        {
            sawKarabinerConflict = true
        }
        if existing.filter({ $0.source == mapping.source }) == [mapping] {
            if let saved {
                if owned == nil {
                    save(nil, for: id)
                } else if saved.pending != nil || saved.installed != mapping {
                    save(SavedMapping(original: saved.original, installed: mapping), for: id)
                }
            }
            return .unchanged
        }
        let wanted = mapping.replacingSource(in: existing)
        let original = owned != nil ? saved?.original ?? [] : existing.filter { $0.source == mapping.source }
        let pending = SavedMapping(
            original: original, installed: owned ?? mapping, pending: owned == nil ? nil : mapping)
        // Journal both sides of a route change before the HID write can outlive this process.
        save(pending, for: id)
        guard system.setKeyMappings(wanted, on: keyboard) else {
            save(saved, for: id)
            return .failed
        }
        save(SavedMapping(original: original, installed: mapping), for: id)
        return .changed
    }

    private func save(_ mapping: SavedMapping?, for id: String) {
        savedMappings[id] = mapping
        if savedMappings.isEmpty {
            defaults.removeObject(forKey: recoveryKey)
        } else if let bootSessionID,
            let data = try? JSONEncoder().encode(
                Recovery(bootSessionID: bootSessionID, keyboards: savedMappings))
        {
            defaults.set(data, forKey: recoveryKey)
        }
    }

    private static func currentBootSessionID() -> String? {
        var size = 0
        guard sysctlbyname("kern.bootsessionuuid", nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var bytes = [UInt8](repeating: 0, count: size)
        let status = bytes.withUnsafeMutableBytes {
            sysctlbyname("kern.bootsessionuuid", $0.baseAddress, &size, nil, 0)
        }
        guard status == 0 else { return nil }
        return String(bytes: bytes.prefix { $0 != 0 }, encoding: .utf8)
    }
}
