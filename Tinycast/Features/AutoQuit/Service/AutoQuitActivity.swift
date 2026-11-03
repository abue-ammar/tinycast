import CoreAudio
import CoreMediaIO
import Foundation

/// Hides screen-capture devices, whose list asks for screen-recording permission.
@MainActor
final class AutoQuitActivity {
    struct Snapshot: Equatable, Sendable {
        var recording: Bool
        var playing: Set<String>
    }

    private var onChange: ((Snapshot) -> Void)?
    private var last: Snapshot?
    private var refreshScheduled = false
    private var camerasConfigured = false
    private var processWatches: [AudioWatch] = []
    private var cameraWatches: [CameraWatch] = []
    private var systemWatches: [AudioWatch] = []
    private var systemCameraWatches: [CameraWatch] = []

    func start(onChange: @escaping (Snapshot) -> Void) {
        guard self.onChange == nil else { return }
        self.onChange = onChange
        suppressScreenCaptureDevices()
        if let watch = watchAudio(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyProcessObjectList) {
            systemWatches.append(watch)
        }
        if let watch = watchCamera(CMIOObjectID(kCMIOObjectSystemObject), selector(kCMIOHardwarePropertyDevices)) {
            systemCameraWatches.append(watch)
        }
        refresh()
    }

    private func scheduleRefresh() {
        guard !refreshScheduled else { return }
        refreshScheduled = true
        Task { @MainActor in
            refreshScheduled = false
            refresh()
        }
    }

    private func refresh() {
        let processes = objectIDs(
            AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyProcessObjectList)
        setProcessWatches(processes)
        let cameras = cameraIDs()
        setCameraWatches(cameras)

        var recording = false
        var playing: Set<String> = []
        for process in processes {
            if flag(process, kAudioProcessPropertyIsRunningInput) { recording = true }
            guard
                let bundleID = bundleID(of: process),
                AutoQuitSchedule.mediaPlayers.contains(bundleID),
                flag(process, kAudioProcessPropertyIsRunningOutput)
            else { continue }
            playing.insert(bundleID)
        }
        if cameras.contains(where: { cameraFlag($0, selector(kCMIODevicePropertyDeviceIsRunningSomewhere)) }) {
            recording = true
        }
        let snapshot = Snapshot(recording: recording, playing: playing)
        guard snapshot != last else { return }
        last = snapshot
        onChange?(snapshot)
    }

    private func setProcessWatches(_ ids: [AudioObjectID]) {
        let wanted = Set(ids)
        guard wanted != Set(processWatches.map(\.object)) else { return }
        for watch in processWatches { remove(watch) }
        processWatches = ids.flatMap { id in
            [kAudioProcessPropertyIsRunningInput, kAudioProcessPropertyIsRunningOutput].compactMap {
                watchAudio(id, $0)
            }
        }
    }

    private func setCameraWatches(_ ids: [CMIOObjectID]) {
        let wanted = Set(ids)
        guard wanted != Set(cameraWatches.map(\.object)) else { return }
        for watch in cameraWatches { remove(watch) }
        cameraWatches = ids.compactMap {
            watchCamera($0, selector(kCMIODevicePropertyDeviceIsRunningSomewhere))
        }
    }

    /// Off before the first device query, so the list is cameras only.
    private func suppressScreenCaptureDevices() {
        guard !camerasConfigured else { return }
        camerasConfigured = true
        var address = cameraAddress(selector(kCMIOHardwarePropertyAllowScreenCaptureDevices))
        var allow: UInt32 = 0
        CMIOObjectSetPropertyData(
            CMIOObjectID(kCMIOObjectSystemObject), &address, 0, nil,
            UInt32(MemoryLayout<UInt32>.size), &allow)
    }

    private func cameraIDs() -> [CMIOObjectID] {
        var address = cameraAddress(selector(kCMIOHardwarePropertyDevices))
        var size: UInt32 = 0
        let object = CMIOObjectID(kCMIOObjectSystemObject)
        guard CMIOObjectGetPropertyDataSize(object, &address, 0, nil, &size) == noErr, size > 0
        else { return [] }
        var ids = [CMIOObjectID](repeating: 0, count: Int(size) / MemoryLayout<CMIOObjectID>.size)
        var used: UInt32 = 0
        guard CMIOObjectGetPropertyData(object, &address, 0, nil, size, &used, &ids) == noErr else {
            return []
        }
        return ids
    }

    private func watchAudio(
        _ object: AudioObjectID, _ selector: AudioObjectPropertySelector
    ) -> AudioWatch? {
        var address = audioAddress(selector)
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            Task { @MainActor in self?.scheduleRefresh() }
        }
        guard AudioObjectAddPropertyListenerBlock(object, &address, .main, block) == noErr else {
            return nil
        }
        return AudioWatch(object: object, selector: selector, block: block)
    }

    private func watchCamera(
        _ object: CMIOObjectID, _ selector: CMIOObjectPropertySelector
    ) -> CameraWatch? {
        var address = cameraAddress(selector)
        let block: CMIOObjectPropertyListenerBlock = { [weak self] _, _ in
            Task { @MainActor in self?.scheduleRefresh() }
        }
        guard CMIOObjectAddPropertyListenerBlock(object, &address, .main, block) == noErr else {
            return nil
        }
        return CameraWatch(object: object, selector: selector, block: block)
    }

    private func remove(_ watch: AudioWatch) {
        var address = audioAddress(watch.selector)
        AudioObjectRemovePropertyListenerBlock(watch.object, &address, .main, watch.block)
    }

    private func remove(_ watch: CameraWatch) {
        var address = cameraAddress(watch.selector)
        CMIOObjectRemovePropertyListenerBlock(watch.object, &address, .main, watch.block)
    }

    private func objectIDs(
        _ object: AudioObjectID, _ selector: AudioObjectPropertySelector
    ) -> [AudioObjectID] {
        var address = audioAddress(selector)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(object, &address, 0, nil, &size) == noErr, size > 0
        else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &ids) == noErr else {
            return []
        }
        return ids.filter { $0 != kAudioObjectUnknown }
    }

    private func flag(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> Bool {
        var address = audioAddress(selector)
        guard AudioObjectHasProperty(object, &address) else { return false }
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr else {
            return false
        }
        return value != 0
    }

    private func cameraFlag(_ object: CMIOObjectID, _ selector: CMIOObjectPropertySelector) -> Bool {
        var address = cameraAddress(selector)
        guard CMIOObjectHasProperty(object, &address) else { return false }
        var value: UInt32 = 0
        var used: UInt32 = 0
        guard
            CMIOObjectGetPropertyData(
                object, &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &used, &value) == noErr
        else { return false }
        return value != 0
    }

    /// The property hands back a +1 string.
    private func bundleID(of process: AudioObjectID) -> String? {
        var address = audioAddress(kAudioProcessPropertyBundleID)
        var unmanaged: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = withUnsafeMutablePointer(to: &unmanaged) { pointer in
            AudioObjectGetPropertyData(process, &address, 0, nil, &size, pointer)
        }
        guard status == noErr else { return nil }
        return unmanaged?.takeRetainedValue() as String?
    }

    private func audioAddress(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
    }

    private func cameraAddress(_ selector: CMIOObjectPropertySelector) -> CMIOObjectPropertyAddress {
        CMIOObjectPropertyAddress(
            mSelector: selector, mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))
    }

    /// The four-character constants import as `Int`.
    private func selector(_ raw: Int) -> CMIOObjectPropertySelector {
        CMIOObjectPropertySelector(raw)
    }
}

private struct AudioWatch {
    var object: AudioObjectID
    var selector: AudioObjectPropertySelector
    var block: AudioObjectPropertyListenerBlock
}

private struct CameraWatch {
    var object: CMIOObjectID
    var selector: CMIOObjectPropertySelector
    var block: CMIOObjectPropertyListenerBlock
}
