import Foundation
import CoreGraphics

@main
struct MonitorControlTests {
    static func main() {
        packets()
        identities()
        keys()
        routing()
        fineAdjustments()
        feedback()
        audioIgnoresPointer()
        queue()
        adjustments()
        print("Monitor control tests passed")
    }

    static func packets() {
        assert(MonitorDDCPacket.request(.brightness) == [0x82, 0x01, 0x10, 0xFD])
        assert(MonitorDDCPacket.request(.volume, value: 50) == [0x84, 0x03, 0x62, 0, 50, 0xE8])
        var response: [UInt8] = [0x6E, 0x88, 2, 0, 0x10, 0, 0, 100, 0, 40]
        response.append(response.reduce(0x50, ^))
        assert(MonitorDDCPacket.response(response, control: .brightness) == .init(current: 40, maximum: 100))
        assert(MonitorDDCPacket.response(response, control: .volume) == nil)
        let lgBrightness: [UInt8] = [0x6E, 0, 2, 0, 0x10, 0, 0, 100, 0, 100, 0xA4]
        assert(MonitorDDCPacket.response(lgBrightness, control: .brightness)?.current == 100)
        let lgMute: [UInt8] = [0x6E, 0, 2, 0, 0x8D, 0, 0, 100, 0, 2, 0x5F]
        assert(MonitorDDCPacket.response(lgMute, control: .mute)?.current == 2)
        assert(MonitorDDCPacket.response(Array(response.dropLast()), control: .brightness) == nil)
        for index in response.indices {
            var corrupt = response
            corrupt[index] ^= 1
            assert(MonitorDDCPacket.response(corrupt, control: .brightness) == nil)
        }
        var unsupported = response
        unsupported[3] = 1
        unsupported[10] = unsupported.dropLast().reduce(0x50, ^)
        assert(MonitorDDCPacket.response(unsupported, control: .brightness) == nil)
        var invalidRange = response
        invalidRange[9] = 101
        invalidRange[10] = invalidRange.dropLast().reduce(0x50, ^)
        assert(MonitorDDCPacket.response(invalidRange, control: .brightness) == nil)
        let zero = MonitorControlValue(current: 0, maximum: 100)
        assert(zero.stepped(up: false, fine: false).current == 0)
        assert(zero.stepped(up: true, fine: false).current == 6)
        assert(zero.stepped(up: true, fine: true).current == 2)
        assert(MonitorControlValue(current: 100, maximum: 100).stepped(up: true, fine: false).current == 100)
        assert(MonitorControlValue(current: 1, maximum: 2).toggledMute.current == 2)
        assert(MonitorControlValue(current: 2, maximum: 2).toggledMute.current == 1)
        assert(MonitorControlValue(current: 0, maximum: 10).stepped(up: true, fine: true).current == 1)
        var climbing = zero
        for _ in 0..<16 { climbing = climbing.stepped(up: true, fine: false) }
        assert(climbing.current == 100)
        for _ in 0..<16 { climbing = climbing.stepped(up: false, fine: false) }
        assert(climbing.current == 0)
    }

    static func identities() {
        let first = MonitorIdentity(location: "port-1", name: "LG 27", serial: 42, edidVendor: "1234", edidProduct: "ABCD")
        var second = first
        second.location = "port-2"
        second.serial = 43
        assert(MonitorIdentity.matches(displays: [first, second], services: [second, first]) == [0: 1, 1: 0])
        assert(MonitorIdentity.matches(displays: [first], services: [first, first]).isEmpty)
        assert(MonitorIdentity.matches(displays: [first, first], services: [first]).isEmpty)
        assert(MonitorIdentity.matches(displays: [MonitorIdentity()], services: [first]).isEmpty)
        assert(MonitorIdentity.audioTarget(name: "LG HDR DQHD", displays: [1: "LG HDR DQHD"], displayTransport: true) == 1)
        assert(MonitorIdentity.audioTarget(name: "LG 27", displays: [1: "LG 32"], displayTransport: true) == nil)
        assert(MonitorIdentity.audioTarget(name: "LG 27", displays: [1: "LG 27", 2: "LG 27"], displayTransport: true) == nil)
        assert(MonitorIdentity.audioTarget(name: "LG 27", displays: [1: "LG 27"], displayTransport: false) == nil)
    }

    static func key(_ action: MonitorMediaKey.Action, pressed: Bool = true, repeated: Bool = false,
                    flags: UInt64 = 0) -> MonitorMediaKey {
        .init(action: action, pressed: pressed, repeated: repeated, flags: flags, token: action.rawValue)
    }

    static func keys() {
        let decoded = MonitorMediaKey.decode(type: 14, subtype: 8, data: 2 << 16 | 0xA01,
                                             keyCode: 0, repeated: false, flags: 0)
        assert(decoded?.action == .brightnessUp && decoded?.repeated == true && decoded?.pressed == true)
        assert(MonitorMediaKey.decode(type: 14, subtype: 8, data: 16 << 16 | 0xA00,
                                      keyCode: 0, repeated: false, flags: 0) == nil)
        assert(MonitorMediaKey.decode(type: 10, subtype: 0, data: 0,
                                      keyCode: 122, repeated: false, flags: 0) == nil)
        assert(MonitorMediaKey.decode(type: 11, subtype: 0, data: 0,
                                      keyCode: 145, repeated: false, flags: 0)?.pressed == false)
        assert(!key(.brightnessUp, flags: 1 << 19).supportedModifiers)
        assert(key(.brightnessUp, flags: 1 << 19 | 1 << 17).fine)
        assert(!key(.brightnessUp, flags: 1 << 20).supportedModifiers)
    }

    static func routing() {
        var router = MonitorKeyRouting()
        router.enabled = true
        router.fineAdjustments = false
        router.displays = [
            .init(id: 1, name: "LG", bounds: CGRect(x: 0, y: 0, width: 100, height: 100),
                  values: [.brightness: .init(current: 40, maximum: 100), .volume: .init(current: 20, maximum: 100),
                           .mute: .init(current: 2, maximum: 2)]),
            .init(id: 2, name: "Other", bounds: CGRect(x: -100, y: 0, width: 100, height: 100),
                  values: [.brightness: .init(current: 50, maximum: 100)])
        ]
        let point = CGPoint(x: 10, y: 10)
        let first = router.handle(key(.brightnessUp), point: point)
        assert(first.consume && first.command?.displayID == 1 && first.command?.value.current == 44)
        let repeatKey = router.handle(key(.brightnessUp, repeated: true), point: CGPoint(x: -10, y: 10))
        assert(repeatKey.command?.displayID == 1 && repeatKey.command?.value.current == 50)
        assert(router.handle(key(.brightnessUp, pressed: false), point: .zero).consume)
        assert(!router.handle(key(.volumeUp), point: point).consume)
        router.audioTarget = 1
        assert(!router.handle(key(.volumeUp, repeated: true), point: point).consume)
        _ = router.handle(key(.volumeUp, pressed: false), point: point)
        assert(router.handle(key(.volumeUp), point: point).command?.value.current == 25)
        assert(router.handle(key(.mute), point: point).command?.value.current == 1)
        assert(router.handle(key(.mute, repeated: true), point: point).command == nil)
        if let first = first.command, let latest = repeatKey.command {
            assert(!router.complete(first, value: .init(current: 46, maximum: 100)))
            assert(router.complete(latest, value: .init(current: 51, maximum: 100)))
            assert(router.displays[0].values[.brightness]?.current == 51)
            assert(router.complete(latest, value: nil))
            assert(!router.handle(key(.brightnessUp), point: point).consume)
        }
        router.generation += 1
        assert(router.handle(key(.volumeUp, repeated: true), point: point).command == nil)
        assert(router.handle(key(.volumeUp, pressed: false), point: point).consume)
        router.enabled = false
        assert(!router.handle(key(.brightnessDown), point: point).consume)
    }

    static func fineAdjustments() {
        assert(MonitorKeyRouting().fineAdjustments)
        let optionShift: UInt64 = 1 << 19 | 1 << 17
        let point = CGPoint(x: 50, y: 50)
        var router = MonitorKeyRouting()
        router.enabled = true
        router.audioTarget = 1
        for preference in [true, false] {
            router.fineAdjustments = preference
            for flags: UInt64 in [0, 1 << 17, optionShift] {
                let fine = preference != (flags == optionShift)
                for action: MonitorMediaKey.Action in [.brightnessUp, .brightnessDown, .volumeUp, .volumeDown] {
                    let initial = MonitorControlValue(current: 64, maximum: 128)
                    router.displays = [
                        .init(id: 1, name: "Monitor", bounds: CGRect(x: 0, y: 0, width: 100, height: 100),
                              values: [action.control: initial])
                    ]
                    let delta = (fine ? 2 : 8) * (action.up ? 1 : -1)
                    for repeatIndex in 0..<3 {
                        let result = router.handle(key(action, repeated: repeatIndex > 0, flags: flags), point: point)
                        assert(result.consume)
                        assert(result.command?.value.current == UInt16(64 + delta * (repeatIndex + 1)))
                        assert(result.command?.adjustment.apply(to: initial).current == UInt16(64 + delta))
                    }
                    let release = router.handle(key(action, pressed: false, flags: flags), point: point)
                    assert(release.consume && release.command == nil)
                }
            }
            router.displays[0].values[.mute] = .init(current: 2, maximum: 2)
            assert(router.handle(key(.mute), point: point).command?.value.current == 1)
            assert(router.handle(key(.mute, repeated: true), point: point).command == nil)
            assert(router.handle(key(.mute, pressed: false), point: point).consume)
            assert(!router.handle(key(.brightnessUp, flags: 1 << 19), point: point).consume)
            assert(!router.handle(key(.brightnessUp, pressed: false), point: point).consume)
        }
        router.displays[0].values[.brightness] = .init(current: 64, maximum: 128)
        router.fineAdjustments = true
        assert(router.handle(key(.brightnessUp), point: point).command?.value.current == 66)
        router.fineAdjustments = false
        assert(router.handle(key(.brightnessUp, repeated: true), point: point).command?.value.current == 72)
        assert(router.handle(key(.brightnessUp, pressed: false), point: point).consume)
        router.enabled = false
        assert(!router.handle(key(.brightnessUp), point: point).consume)
    }

    static func feedback() {
        var state = MonitorFeedbackState()
        let first = MonitorKeyRouting.Command(generation: 1, displayID: 1, control: .brightness,
            value: .init(current: 50, maximum: 100), revision: 1,
            adjustment: .level(offset: 1, minimum: 1, maximum: 100))
        let latest = MonitorKeyRouting.Command(generation: 1, displayID: 1, control: .brightness,
            value: .init(current: 80, maximum: 100), revision: 20, adjustment: first.adjustment)
        state.begin(first)
        state.begin(latest)
        assert(!state.finish(first, failed: false) && state.pending)
        assert(state.latest?.value.current == 80)
        assert(state.finish(latest, failed: false) && !state.pending)
        state.begin(latest)
        assert(state.finish(first, failed: true) && !state.pending)
        state = MonitorFeedbackState()
        assert(!state.finish(latest, failed: false) && !state.pending)
    }

    static func audioIgnoresPointer() {
        var router = MonitorKeyRouting()
        router.enabled = true
        router.audioTarget = 1
        let values: [MonitorControlKind: MonitorControlValue] = [
            .brightness: .init(current: 50, maximum: 100), .volume: .init(current: 20, maximum: 100),
            .mute: .init(current: 2, maximum: 2)
        ]
        router.displays = [
            .init(id: 1, name: "Audio monitor", bounds: CGRect(x: 0, y: 0, width: 100, height: 100), values: values),
            .init(id: 2, name: "Other monitor", bounds: CGRect(x: 100, y: 0, width: 100, height: 100), values: values)
        ]
        let builtIn = CGPoint(x: -50, y: 50)
        let otherMonitor = CGPoint(x: 150, y: 50)
        for point in [builtIn, otherMonitor, CGPoint(x: 500, y: 500)] {
            for action: MonitorMediaKey.Action in [.volumeUp, .volumeDown, .mute] {
                let press = router.handle(key(action), point: point)
                assert(press.consume && press.command?.displayID == 1)
                assert(router.handle(key(action, pressed: false), point: point).consume)
            }
        }
        assert(!router.handle(key(.brightnessUp), point: builtIn).consume)
        _ = router.handle(key(.brightnessUp, pressed: false), point: builtIn)
        assert(router.handle(key(.brightnessUp), point: otherMonitor).command?.displayID == 2)
        assert(router.handle(key(.volumeUp), point: builtIn).command?.displayID == 1)
        assert(router.handle(key(.volumeUp, repeated: true), point: otherMonitor).command?.displayID == 1)
        router.audioTarget = 2
        let repeatAfterSwitch = router.handle(key(.volumeUp, repeated: true), point: builtIn)
        assert(repeatAfterSwitch.consume && repeatAfterSwitch.command == nil)
        assert(router.handle(key(.volumeUp, pressed: false), point: builtIn).consume)
        assert(router.handle(key(.volumeUp), point: builtIn).command?.displayID == 2)
        _ = router.handle(key(.volumeUp, pressed: false), point: builtIn)
        router.audioTarget = nil
        assert(!router.handle(key(.volumeUp), point: .zero).consume)
        assert(!router.handle(key(.mute), point: .zero).consume)
        _ = router.handle(key(.mute, pressed: false), point: .zero)
        router.audioTarget = 2
        router.displays[1].values.removeValue(forKey: .mute)
        assert(!router.handle(key(.mute), point: builtIn).consume)
    }

    static func queue() {
        var queue = MonitorCommandQueue()
        queue.reset(generation: 2)
        for revision in 1...20 {
            queue.enqueue(.init(generation: 2, displayID: 1, control: .brightness,
                                value: .init(current: UInt16(revision), maximum: 100), revision: UInt64(revision),
                                adjustment: .level(offset: 0, minimum: revision, maximum: revision)))
        }
        assert(queue.next()?.value.current == 20)
        assert(queue.next() == nil)
        queue.enqueue(.init(generation: 1, displayID: 1, control: .brightness,
                            value: .init(current: 90, maximum: 100), revision: 21,
                            adjustment: .level(offset: 0, minimum: 90, maximum: 90)))
        assert(queue.next() == nil)
        queue.enqueue(.init(generation: 2, displayID: 1, control: .volume,
                            value: .init(current: 10, maximum: 100), revision: 22,
                            adjustment: .level(offset: 0, minimum: 10, maximum: 10)))
        queue.reset(generation: 3)
        assert(queue.next() == nil)
    }

    static func adjustments() {
        let increase = MonitorControlAdjustment.level(offset: 6, minimum: 6, maximum: 100)
        let decrease = MonitorControlAdjustment.level(offset: -6, minimum: 0, maximum: 94)
        for raw in 0...100 {
            let value = MonitorControlValue(current: UInt16(raw), maximum: 100)
            for first in [increase, decrease] {
                for second in [increase, decrease] {
                    assert(first.followed(by: second).apply(to: value) == second.apply(to: first.apply(to: value)))
                }
            }
        }
        let original = MonitorControlValue(current: 24, maximum: 100)
        assert(increase.followed(by: increase).apply(to: original).current == 36)
        assert(increase.apply(to: .init(current: 50, maximum: 100)).current == 56)
        assert(MonitorControlAdjustment.mute(toggle: true).followed(by: .mute(toggle: true))
            .apply(to: .init(current: 2, maximum: 100)).current == 2)
    }
}
