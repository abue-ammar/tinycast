import CoreAudio
import Foundation
import Synchronization

@MainActor
enum SystemActionRunner {}

private struct AudioFixture: Sendable {
    var device: AudioDeviceID = 78
    var muted: UInt32 = 0
    var hasMute = true
    var settable = true
    var lookupStatus: OSStatus = noErr
    var readStatus: OSStatus = noErr
    var writeStatus: OSStatus = noErr
    var appliesWrite = true
    var delayedReads = 0
    var pendingMute: UInt32?
    var nextDefaultDevice: AudioDeviceID?
    var defaultLookups = 0
    var controlDevices: [AudioDeviceID] = []
    var writes: [UInt32] = []
    var invalidAddress = false

    mutating func check(_ device: AudioDeviceID, _ address: AudioObjectPropertyAddress) {
        controlDevices.append(device)
        if address.mSelector != kAudioDevicePropertyMute
            || address.mScope != kAudioDevicePropertyScopeInput
            || address.mElement != kAudioObjectPropertyElementMain
        {
            invalidAddress = true
        }
    }
}

private let audio = Mutex(AudioFixture())

// These module-local functions keep the shipped CoreAudio calls away from real hardware.
func AudioObjectGetPropertyData(
    _ device: AudioObjectID, _ address: UnsafePointer<AudioObjectPropertyAddress>,
    _ qualifierSize: UInt32, _ qualifier: UnsafeRawPointer?,
    _ size: UnsafeMutablePointer<UInt32>, _ data: UnsafeMutableRawPointer
) -> OSStatus {
    audio.withLock { fixture in
        if address.pointee.mSelector == kAudioHardwarePropertyDefaultInputDevice {
            fixture.defaultLookups += 1
            if device != kAudioObjectSystemObject
                || address.pointee.mScope != kAudioObjectPropertyScopeGlobal
                || address.pointee.mElement != kAudioObjectPropertyElementMain
            {
                fixture.invalidAddress = true
            }
            data.storeBytes(of: fixture.device, as: AudioDeviceID.self)
            return fixture.lookupStatus
        }
        fixture.check(device, address.pointee)
        if let pending = fixture.pendingMute, fixture.appliesWrite {
            if fixture.delayedReads == 0 {
                fixture.muted = pending
            } else {
                fixture.delayedReads -= 1
            }
        }
        data.storeBytes(of: fixture.muted, as: UInt32.self)
        return fixture.readStatus
    }
}

func AudioObjectHasProperty(
    _ device: AudioObjectID, _ address: UnsafePointer<AudioObjectPropertyAddress>
) -> Bool {
    audio.withLock { fixture in
        fixture.check(device, address.pointee)
        return fixture.hasMute
    }
}

func AudioObjectIsPropertySettable(
    _ device: AudioObjectID, _ address: UnsafePointer<AudioObjectPropertyAddress>,
    _ settable: UnsafeMutablePointer<DarwinBoolean>
) -> OSStatus {
    audio.withLock { fixture in
        fixture.check(device, address.pointee)
        settable.pointee = DarwinBoolean(fixture.settable)
        return noErr
    }
}

func AudioObjectSetPropertyData(
    _ device: AudioObjectID, _ address: UnsafePointer<AudioObjectPropertyAddress>,
    _ qualifierSize: UInt32, _ qualifier: UnsafeRawPointer?,
    _ size: UInt32, _ data: UnsafeRawPointer
) -> OSStatus {
    audio.withLock { fixture in
        fixture.check(device, address.pointee)
        let value = data.load(as: UInt32.self)
        fixture.writes.append(value)
        if fixture.writeStatus == noErr { fixture.pendingMute = value }
        if let next = fixture.nextDefaultDevice { fixture.device = next }
        return fixture.writeStatus
    }
}

@main
@MainActor
struct MicrophoneMuteTests {
    static var failures = 0
    static var passes = 0

    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if condition() {
            passes += 1
        } else {
            failures += 1
            print("FAIL: \(message)")
        }
    }

    private static func reset(_ fixture: AudioFixture = AudioFixture()) {
        audio.withLock { $0 = fixture }
    }

    static func expectToggle(_ muted: Bool) async {
        do {
            let result = try await SystemActionRunner.toggleMicrophoneMute()
            expect(result == muted, "feedback matches the confirmed microphone state")
            audio.withLock { fixture in
                expect(fixture.muted == (muted ? 1 : 0), "the native mute state changed")
                expect(fixture.writes == [muted ? 1 : 0], "mute is written exactly once")
                expect(!fixture.invalidAddress, "only input mute and the default input are accessed")
            }
        } catch {
            expect(false, "unexpected failure: \(error)")
        }
    }

    static func expectFailure(_ message: String, writes: Int = 0) async {
        do {
            _ = try await SystemActionRunner.toggleMicrophoneMute()
            expect(false, "an unconfirmed change must not report success")
        } catch let failure as SystemActionFailure {
            expect(failure.message.contains(message), "the failure explains \(message)")
            audio.withLock { fixture in
                expect(fixture.writes.count == writes, "failure performs only expected writes")
                expect(!fixture.invalidAddress, "failure does not access output audio or gain")
            }
        } catch {
            expect(false, "unexpected error type: \(error)")
        }
    }

    static func main() async {
        reset()
        await expectToggle(true)

        reset(AudioFixture(muted: 1))
        await expectToggle(false)

        reset(AudioFixture(delayedReads: 2))
        await expectToggle(true)

        reset(AudioFixture(nextDefaultDevice: 99))
        await expectToggle(true)
        audio.withLock { fixture in
            expect(fixture.defaultLookups == 1, "one activation resolves the default input once")
            expect(fixture.controlDevices.allSatisfy { $0 == 78 }, "readback stays on the written device")
        }
        reset(AudioFixture(device: 99, muted: 1))
        await expectToggle(false)
        expect(audio.withLock { $0.controlDevices.allSatisfy { $0 == 99 } }, "the next toggle follows the new input")

        reset(AudioFixture(device: kAudioObjectUnknown))
        await expectFailure("No audio input device")
        reset(AudioFixture(lookupStatus: -1))
        await expectFailure("No audio input device")
        reset(AudioFixture(hasMute: false))
        await expectFailure("does not support software mute")
        reset(AudioFixture(settable: false))
        await expectFailure("controlled externally")
        reset(AudioFixture(readStatus: -2))
        await expectFailure("could not read microphone mute")
        reset(AudioFixture(writeStatus: -3))
        await expectFailure("could not change microphone mute", writes: 1)
        reset(AudioFixture(appliesWrite: false))
        await expectFailure("did not confirm", writes: 1)

        print("\(passes) passed, \(failures) failed")
        if failures > 0 { exit(1) }
    }
}
