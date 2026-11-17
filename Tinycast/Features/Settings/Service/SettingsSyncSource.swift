import Foundation
import OSLog

@MainActor
final class SettingsSyncSource: SyncSource {
    private static let logger = Logger(subsystem: "com.tinycast", category: "CloudSync")

    let id = SyncSourceID.settings
    private let bindings: [String: SettingsFileBinding]
    private let commit: () -> [SettingsFileIssue]
    private let settings: AppSettings

    init(bindings: [SettingsFileBinding], commit: @escaping () -> [SettingsFileIssue], settings: AppSettings)
    {
        self.bindings = Dictionary(
            uniqueKeysWithValues: bindings.filter { SyncSettingScope.category(of: $0.key) != nil }
                .map { ($0.key.rawValue, $0) })
        self.commit = commit
        self.settings = settings
    }

    func observe() {
        _ = settings.launchAtLogin
        for binding in bindings.values { _ = binding.read() }
    }

    func snapshot() async -> [String: String]? {
        var versions: [String: String] = [:]
        for key in bindings.keys + [SyncSettingScope.launchAtLoginKey] {
            versions[key] = payload(key).map(SyncVersion.of)
        }
        return versions
    }

    func payload(for key: String) async -> Data? {
        payload(key)
    }

    func apply(_ changes: SyncChanges) async -> Set<String> {
        var issues: [SettingsFileIssue] = []
        for (key, payload) in changes.upserts {
            if key == SyncSettingScope.launchAtLoginKey {
                if let enabled = SyncPayload.decode(Bool.self, from: payload),
                    enabled != settings.launchAtLogin
                {
                    settings.launchAtLogin = enabled
                }
                continue
            }
            guard
                let binding = bindings[key],
                let value = (try? SettingsFileFormat.parse(payload))?.values[binding.key]
            else { continue }
            issues += binding.write(value)
        }
        issues += commit()
        if let summary = SettingsFileIssue.summary(issues) {
            Self.logger.notice("Synced settings kept this Mac's value: \(summary, privacy: .public)")
        }
        return []
    }

    private func payload(_ key: String) -> Data? {
        if key == SyncSettingScope.launchAtLoginKey { return SyncPayload.encode(settings.launchAtLogin) }
        guard let binding = bindings[key] else { return nil }
        return SettingsFileFormat.render([binding.key: binding.read()])
    }
}
