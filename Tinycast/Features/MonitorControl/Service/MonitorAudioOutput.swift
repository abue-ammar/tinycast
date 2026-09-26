import CoreAudio
import Foundation

enum MonitorAudioOutput {
    static func target(displays: [MonitorKeyRouting.Display]) -> UInt32? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var device: AudioDeviceID = 0
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address,
                                         0, nil, &size, &device) == noErr, device != 0 else { return nil }
        address.mSelector = kAudioDevicePropertyTransportType
        var transport: UInt32 = 0
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &transport) == noErr else { return nil }
        address.mSelector = kAudioObjectPropertyName
        var reference: Unmanaged<CFString>?
        size = UInt32(MemoryLayout.size(ofValue: reference))
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &reference) == noErr,
            let name = reference?.takeRetainedValue() else { return nil }
        return MonitorIdentity.audioTarget(
            name: name as String, displays: Dictionary(uniqueKeysWithValues: displays.map { ($0.id, $0.name) }),
            displayTransport: transport == kAudioDeviceTransportTypeHDMI || transport == kAudioDeviceTransportTypeDisplayPort)
    }
}
