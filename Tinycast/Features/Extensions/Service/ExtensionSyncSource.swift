import Foundation
import OSLog

/// Store extensions and plain preferences; installs wait for Extensions, the consent to run code.
@MainActor
final class ExtensionSyncSource: SyncSource {
    private struct Payload: Codable {
        let handle: String
        let preferences: [String: Preference]
    }

    private enum Preference: Codable, Equatable {
        case string(String), bool(Bool), number(Double)
    }

    private static let logger = Logger(subsystem: "com.tinycast", category: "CloudSync")
    private static let syncedKinds: Set<ExtensionPreferenceSchema.Kind> = [.textfield, .checkbox, .dropdown]
    /// An install that failed is tried again at most this often, not on every pass.
    private static let retryInterval: Duration = .seconds(3600)

    let id = SyncSourceID.extensions
    private let manager: ExtensionManager
    private var installing: Set<String> = []
    private var lastAttempt: [String: ContinuousClock.Instant] = [:]

    init(manager: ExtensionManager) {
        self.manager = manager
    }

    func observe() {
        _ = manager.isEnabled
        _ = manager.installed
    }

    func snapshot() async -> [String: String]? {
        guard manager.isEnabled else { return nil }
        return SyncPayload.snapshot(
            Dictionary(
                uniqueKeysWithValues: manager.storeInstalled.map { ($0.manifest.name, payload(of: $0)) }))
    }

    func payload(for key: String) async -> Data? {
        manager.storeInstalled.first { $0.manifest.name == key }.flatMap {
            SyncPayload.encode(payload(of: $0))
        }
    }

    func apply(_ changes: SyncChanges) async -> Set<String> {
        guard manager.isEnabled else { return Set(changes.upserts.keys).union(changes.deletions) }
        for key in changes.deletions {
            guard let installed = manager.storeInstalled.first(where: { $0.manifest.name == key }) else {
                continue
            }
            await manager.uninstall(installed)
        }
        var deferred: Set<String> = []
        for (key, data) in changes.upserts {
            guard let payload = SyncPayload.decode(Payload.self, from: data) else { continue }
            guard let installed = manager.extensionNamed(key) else {
                install(key, handle: payload.handle)
                deferred.insert(key)
                continue
            }
            for schema in Self.syncedSchemas(of: installed) {
                let value = payload.preferences[schema.name].map(Self.value)
                if manager.storage.preference(extension: key, key: schema.name) != value {
                    manager.storage.setPreference(extension: key, key: schema.name, value: value)
                }
            }
        }
        return deferred
    }

    /// Runs beside sync rather than in it: a download can take a while, and the arrival waits.
    private func install(_ name: String, handle: String) {
        let now = ContinuousClock.now
        guard !installing.contains(name), lastAttempt[name].map({ now - $0 > Self.retryInterval }) ?? true
        else {
            return
        }
        installing.insert(name)
        lastAttempt[name] = now
        Task { [weak self] in
            do {
                try await self?.manager.installFromStore(handle: handle, name: name)
            } catch {
                Self.logger.error("Installing synced extension \(name, privacy: .public) failed: \(error)")
            }
            self?.installing.remove(name)
        }
    }

    private func payload(of installed: InstalledExtension) -> Payload {
        var preferences: [String: Preference] = [:]
        for schema in Self.syncedSchemas(of: installed) {
            switch manager.storage.preference(extension: installed.manifest.name, key: schema.name) {
            case .string(let value): preferences[schema.name] = .string(value)
            case .bool(let value): preferences[schema.name] = .bool(value)
            case .number(let value): preferences[schema.name] = .number(value)
            case .application, nil: break
            }
        }
        return Payload(handle: installed.manifest.storeHandle, preferences: preferences)
    }

    private static func syncedSchemas(of installed: InstalledExtension) -> [ExtensionPreferenceSchema] {
        (installed.manifest.preferences + installed.manifest.commands.flatMap(\.preferences))
            .filter { syncedKinds.contains($0.kind) }
    }

    private static func value(_ preference: Preference) -> ExtensionPreferenceValue {
        switch preference {
        case .string(let value): .string(value)
        case .bool(let value): .bool(value)
        case .number(let value): .number(value)
        }
    }
}
