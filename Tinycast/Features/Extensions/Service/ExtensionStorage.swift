import Foundation

/// One JSON file per extension: small, read whole at launch and written rarely.
@MainActor
final class ExtensionStorage {
    private struct Store: Codable {
        var localStorage: [String: StoredValue] = [:]
        var caches: [String: [String: String]] = [:]
        var preferences: [String: StoredValue] = [:]
        /// `updateCommandMetadata` overrides and background-refresh bookkeeping, per command name.
        var metadata: [String: CommandMetadata] = [:]

        /// A file predating a key still loads; synthesis would discard the whole file instead.
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            localStorage =
                try container.decodeIfPresent([String: StoredValue].self, forKey: .localStorage)
                ?? [:]
            caches =
                try container.decodeIfPresent([String: [String: String]].self, forKey: .caches)
                ?? [:]
            preferences =
                try container.decodeIfPresent([String: StoredValue].self, forKey: .preferences)
                ?? [:]
            metadata =
                try container.decodeIfPresent([String: CommandMetadata].self, forKey: .metadata)
                ?? [:]
        }

        init() {}
    }

    /// What `updateCommandMetadata` wrote plus what the scheduler needs; backup-exempt by location.
    struct CommandMetadata: Codable, Sendable, Equatable {
        /// Set by `updateCommandMetadata`, cleared by `null`; nil falls back to the manifest subtitle.
        var subtitle: String?
        /// Off until the first manual run or the Settings toggle, exactly as in Raycast.
        var backgroundEnabled = false
        var lastRun: Date?
        var lastError: String?
        var consecutiveFailures = 0

        /// Same tolerance as the store: a partial record keeps its defaults.
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            subtitle = try container.decodeIfPresent(String.self, forKey: .subtitle)
            backgroundEnabled =
                try container.decodeIfPresent(Bool.self, forKey: .backgroundEnabled) ?? false
            lastRun = try container.decodeIfPresent(Date.self, forKey: .lastRun)
            lastError = try container.decodeIfPresent(String.self, forKey: .lastError)
            consecutiveFailures =
                try container.decodeIfPresent(Int.self, forKey: .consecutiveFailures) ?? 0
        }

        init() {}
    }

    /// `LocalStorage` accepts strings, numbers and booleans and must return them with their type.
    enum StoredValue: Codable, Sendable, Equatable {
        case string(String)
        case number(Double)
        case bool(Bool)

        var jsonValue: Any {
            switch self {
            case .string(let value): return value
            case .number(let value): return value
            case .bool(let value): return value
            }
        }

        init?(renderValue: RenderValue) {
            switch renderValue {
            case .string(let value): self = .string(value)
            case .number(let value): self = .number(value)
            case .bool(let value): self = .bool(value)
            default: return nil
            }
        }

        init(preference: ExtensionPreferenceValue) {
            switch preference {
            case .string(let value): self = .string(value)
            case .number(let value): self = .number(value)
            case .bool(let value): self = .bool(value)
            }
        }

        var preferenceValue: ExtensionPreferenceValue {
            switch self {
            case .string(let value): return .string(value)
            case .number(let value): return .number(value)
            case .bool(let value): return .bool(value)
            }
        }
    }

    private let directory: URL
    private var stores: [String: Store] = [:]
    /// Writes are coalesced, so a busy `Cache` doesn't hit the disk per key.
    private var dirty: Set<String> = []
    private var flushTask: Task<Void, Never>?

    init(directory: URL) {
        self.directory = directory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    // MARK: - LocalStorage

    func localStorageValue(extension name: String, key: String) -> StoredValue? {
        store(for: name).localStorage[key]
    }

    func allLocalStorage(extension name: String) -> [String: StoredValue] {
        store(for: name).localStorage
    }

    func setLocalStorage(extension name: String, key: String, value: StoredValue) {
        mutate(name) { $0.localStorage[key] = value }
    }

    func removeLocalStorage(extension name: String, key: String) {
        mutate(name) { $0.localStorage.removeValue(forKey: key) }
    }

    func clearLocalStorage(extension name: String) {
        mutate(name) { $0.localStorage.removeAll() }
    }

    // MARK: - Cache

    func caches(extension name: String) -> [String: [String: String]] {
        store(for: name).caches
    }

    /// `nil` removes the key; a `nil` key clears the namespace.
    func setCache(extension name: String, namespace: String, key: String?, value: String?) {
        mutate(name) { store in
            guard let key else {
                store.caches[namespace] = [:]
                return
            }
            var bucket = store.caches[namespace] ?? [:]
            if let value { bucket[key] = value } else { bucket.removeValue(forKey: key) }
            store.caches[namespace] = bucket
        }
    }

    func clearCache(extension name: String, namespace: String) {
        mutate(name) { $0.caches[namespace] = [:] }
    }

    // MARK: - Preferences

    func preference(extension name: String, key: String) -> ExtensionPreferenceValue? {
        store(for: name).preferences[key]?.preferenceValue
    }

    func setPreference(extension name: String, key: String, value: ExtensionPreferenceValue?) {
        mutate(name) { store in
            if let value {
                store.preferences[key] = StoredValue(preference: value)
            } else {
                store.preferences.removeValue(forKey: key)
            }
        }
    }

    /// Manifest defaults overlaid with the user's — what `getPreferenceValues()` sees.
    func resolvedPreferences(
        extension name: String, schemas: [ExtensionPreferenceSchema]
    ) -> [String: ExtensionPreferenceValue] {
        var resolved: [String: ExtensionPreferenceValue] = [:]
        for schema in schemas {
            resolved[schema.name] = preference(extension: name, key: schema.name) ?? schema.effectiveDefault
        }
        return resolved
    }

    /// A command with an unset required preference must not run, exactly as in Raycast.
    func missingRequiredPreferences(
        extension name: String, schemas: [ExtensionPreferenceSchema]
    ) -> [ExtensionPreferenceSchema] {
        schemas.filter { schema in
            guard schema.required else { return false }
            let value = preference(extension: name, key: schema.name) ?? schema.effectiveDefault
            if case .string(let text) = value { return text.isEmpty }
            return false
        }
    }

    func removeAll(extension name: String) {
        stores.removeValue(forKey: name)
        try? FileManager.default.removeItem(at: fileURL(for: name))
    }

    // MARK: - Command metadata

    func commandMetadata(extension name: String, command: String) -> CommandMetadata {
        store(for: name).metadata[command] ?? CommandMetadata()
    }

    func setSubtitle(_ subtitle: String?, extension name: String, command: String) {
        mutate(name) { $0.metadata[command, default: CommandMetadata()].subtitle = subtitle }
    }

    func setBackgroundEnabled(_ enabled: Bool, extension name: String, command: String) {
        mutate(name) { $0.metadata[command, default: CommandMetadata()].backgroundEnabled = enabled }
    }

    /// Disabling retires the last error with the schedule; a stale warning would outlive its cause.
    func clearBackgroundError(extension name: String, command: String) {
        mutate(name) {
            $0.metadata[command, default: CommandMetadata()].lastError = nil
            $0.metadata[command, default: CommandMetadata()].consecutiveFailures = 0
        }
    }

    /// A manual run counts as a refresh, so the scheduler doesn't re-fire right behind it.
    func activateBackgroundRefresh(extension name: String, command: String, now: Date) {
        mutate(name) {
            $0.metadata[command, default: CommandMetadata()].backgroundEnabled = true
            $0.metadata[command, default: CommandMetadata()].lastRun = now
        }
    }

    func recordBackgroundResult(
        extension name: String, command: String, success: Bool, error: String?, now: Date
    ) {
        mutate(name) {
            $0.metadata[command, default: CommandMetadata()].lastRun = now
            $0.metadata[command, default: CommandMetadata()].lastError = success ? nil : error
            if success {
                $0.metadata[command, default: CommandMetadata()].consecutiveFailures = 0
            } else {
                $0.metadata[command, default: CommandMetadata()].consecutiveFailures += 1
            }
        }
    }

    // MARK: - Persistence

    private func store(for name: String) -> Store {
        if let existing = stores[name] { return existing }
        let loaded =
            (try? Data(contentsOf: fileURL(for: name)))
            .flatMap { try? JSONDecoder().decode(Store.self, from: $0) } ?? Store()
        stores[name] = loaded
        return loaded
    }

    private func mutate(_ name: String, _ body: (inout Store) -> Void) {
        var current = store(for: name)
        body(&current)
        stores[name] = current
        dirty.insert(name)
        scheduleFlush()
    }

    private func scheduleFlush() {
        guard flushTask == nil else { return }
        flushTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            self?.flush()
        }
    }

    func flush() {
        flushTask?.cancel()
        flushTask = nil
        let pending = dirty
        dirty.removeAll()
        for name in pending {
            guard let store = stores[name], let data = try? JSONEncoder().encode(store) else { continue }
            try? data.write(to: fileURL(for: name), options: .atomic)
        }
    }

    private func fileURL(for name: String) -> URL {
        directory.appendingPathComponent("\(ExtensionCatalog.safeName(name)).json")
    }
}
