import CoreAudio
import Foundation

extension SystemActionRunner {
    nonisolated static func toggleMicrophoneMute() async throws -> Bool {
        var deviceAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var device = AudioDeviceID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let deviceStatus = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &deviceAddress, 0, nil, &size, &device)
        guard deviceStatus == noErr, device != kAudioObjectUnknown else {
            throw SystemActionFailure("No audio input device is available.")
        }

        var address = microphoneMuteAddress
        guard AudioObjectHasProperty(device, &address) else {
            throw SystemActionFailure("The current microphone does not support software mute.")
        }
        var settable = DarwinBoolean(false)
        let controlStatus = AudioObjectIsPropertySettable(device, &address, &settable)
        guard controlStatus == noErr, settable.boolValue else {
            throw SystemActionFailure("The current microphone mute is controlled externally.")
        }

        let muted = try !microphoneMuted(on: device)
        var value: UInt32 = muted ? 1 : 0
        try Task.checkCancellation()
        let status = AudioObjectSetPropertyData(
            device, &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value)
        guard status == noErr else {
            throw SystemActionFailure("macOS could not change microphone mute (error \(status)).")
        }

        // CoreAudio applies property writes asynchronously, so feedback waits for the device.
        for _ in 0..<10 {
            if try microphoneMuted(on: device) == muted { return muted }
            try await Task.sleep(for: .milliseconds(50))
        }
        guard try microphoneMuted(on: device) == muted else {
            throw SystemActionFailure("The microphone did not confirm the mute change. Try again.")
        }
        return muted
    }

    nonisolated private static var microphoneMuteAddress: AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain)
    }

    nonisolated private static func microphoneMuted(on device: AudioDeviceID) throws -> Bool {
        var address = microphoneMuteAddress
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value)
        guard status == noErr else {
            throw SystemActionFailure("macOS could not read microphone mute (error \(status)).")
        }
        return value != 0
    }
}
