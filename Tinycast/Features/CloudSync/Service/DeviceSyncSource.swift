import Foundation
import Observation
import SystemConfiguration

@MainActor
@Observable
final class DeviceSyncSource: SyncSource {
    let id = SyncSourceID.device
    private(set) var others: [String: SyncDevice] = [:]
    private(set) var name: String
    @ObservationIgnored private let store: CloudSyncStateStore

    init(store: CloudSyncStateStore) {
        self.store = store
        name = store.state.deviceName ?? Self.computerName
        others = store.state.devices
    }

    var deviceID: String { store.state.deviceID }

    static var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
    }

    func rename(to newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != name else { return }
        name = trimmed
        store.update { $0.deviceName = trimmed }
    }

    func forget(_ deviceID: String) {
        others[deviceID] = nil
        store.update { [others] in $0.devices = others }
    }

    func reset() {
        others = [:]
    }

    func observe() {
        _ = name
    }

    func snapshot() async -> [String: String]? {
        SyncPayload.snapshot([deviceID: device])
    }

    func payload(for key: String) async -> Data? {
        key == deviceID ? SyncPayload.encode(device) : nil
    }

    func apply(_ changes: SyncChanges) async -> Set<String> {
        for (key, payload) in changes.upserts {
            guard let device = SyncPayload.decode(SyncDevice.self, from: payload) else { continue }
            if key == deviceID {
                if device.name != name { rename(to: device.name) }
            } else {
                others[key] = device
            }
        }
        for key in changes.deletions where key != deviceID { others[key] = nil }
        store.update { [others] in $0.devices = others }
        return []
    }

    private var device: SyncDevice {
        SyncDevice(
            id: deviceID, name: name,
            appVersion: Self.appVersion,
            lastSeen: SyncDevice.seen(at: .now))
    }

    private static var computerName: String {
        SCDynamicStoreCopyComputerName(nil, nil) as String? ?? String(localized: "This Mac")
    }
}
