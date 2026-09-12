// Standalone contract tests for the pure Space-switch gesture tables and IOHID payload bytes.
import Foundation

@main
@MainActor
struct SpaceGestureTests {
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

    static func expectEqual<T: Equatable>(_ actual: T, _ expected: T, _ message: String) {
        if actual == expected {
            passes += 1
        } else {
            failures += 1
            print("FAIL: \(message) — got \(actual), expected \(expected)")
        }
    }

    // MARK: - Fixtures

    /// The payload is packed little-endian, so every read mirrors how the WindowServer parses it.
    static func read<T: FixedWidthInteger>(_ data: Data, at offset: Int, as type: T.Type) -> T {
        let start = data.startIndex + offset
        return data[start..<start + MemoryLayout<T>.size]
            .reversed()
            .reduce(T(0)) { $0 << 8 | T($1) }
    }

    static func fields(
        _ phase: SpaceGesture.Phase, _ direction: SpaceDirection, augmented: Bool
    ) -> [SpaceGesture.Field] {
        SpaceGesture.fields(
            phase: phase, direction: direction, augmented: augmented, timestamp: 12_345)
    }

    static func value(_ fields: [SpaceGesture.Field], _ raw: UInt32) -> SpaceGesture.FieldValue? {
        fields.first { $0.raw == raw }?.value
    }

    static func double(_ fields: [SpaceGesture.Field], _ raw: UInt32) -> Double? {
        guard case .double(let value) = value(fields, raw) else { return nil }
        return value
    }

    static func integer(_ fields: [SpaceGesture.Field], _ raw: UInt32) -> Int64? {
        guard case .integer(let value) = value(fields, raw) else { return nil }
        return value
    }

    static func main() {
        testDirection()
        testFixedPoint()
        testCommonFields()
        testLegacyFields()
        testAugmentedFields()
        testPayloadShape()
        testPayloadValues()
        testRecordHeader()

        print("\(passes) passed, \(failures) failed")
        if failures > 0 { exit(1) }
    }

    // MARK: - Direction

    static func testDirection() {
        expect(SpaceDirection(.nextSpace) == .next, "next-space maps to the next direction")
        expect(SpaceDirection(.previousSpace) == .previous, "previous-space maps to previous")
        expect(SpaceDirection(.leftHalf) == nil, "a geometry command is not a direction")
        expect(SpaceDirection(.toggleFullscreen) == nil, "fullscreen is not a direction")
        expect(
            WindowCommand.ID.allCases.filter { SpaceDirection($0) != nil }.count == 2,
            "exactly two commands are space switches")
    }

    // MARK: - Fixed point

    static func testFixedPoint() {
        expectEqual(SpaceGesture.fixed1616(0), 0, "zero encodes as zero")
        expectEqual(SpaceGesture.fixed1616(1), 65_536, "one encodes as one whole unit")
        expectEqual(SpaceGesture.fixed1616(-1), -65_536, "negatives encode symmetrically")
        expectEqual(SpaceGesture.fixed1616(0.5), 32_768, "a half encodes as half a unit")
        expectEqual(SpaceGesture.fixed1616(1000), 65_536_000, "the gesture velocity fits in 16.16")
        // The floor is what keeps a deliberately tiny progress from quantizing away to a no-op.
        expectEqual(SpaceGesture.fixed1616(1e-9), 1, "a value below the step floors to +1")
        expectEqual(SpaceGesture.fixed1616(-1e-9), -1, "a negative value below the step floors to -1")
        expectEqual(
            SpaceGesture.fixed1616(Double(Float.leastNonzeroMagnitude)), 1,
            "the legacy progress magnitude survives as +1 rather than vanishing")
    }

    // MARK: - Fields

    static func testCommonFields() {
        for augmented in [false, true] {
            for phase in SpaceGesture.Phase.allCases {
                let table = fields(phase, .next, augmented: augmented)
                expectEqual(integer(table, 55), 30, "the event is a DockControl event")
                expectEqual(integer(table, 110), 23, "the HID type is a dock swipe")
                expectEqual(integer(table, 132), phase.rawValue, "the phase is carried verbatim")
                expectEqual(integer(table, 123), 1, "the motion is horizontal")
                expect(
                    Set(table.map(\.raw)).count == table.count,
                    "no field is written twice for \(phase) augmented=\(augmented)")
            }
        }
        expectEqual(
            SpaceGesture.Phase.allCases.map(\.rawValue), [1, 2, 4],
            "began, changed and ended are posted in order")
    }

    static func testLegacyFields() {
        for phase in SpaceGesture.Phase.allCases {
            let next = fields(phase, .next, augmented: false)
            let previous = fields(phase, .previous, augmented: false)
            expectEqual(
                double(next, 124), Double(Float.leastNonzeroMagnitude),
                "legacy progress is the smallest float, positive for next")
            expectEqual(
                double(previous, 124), -Double(Float.leastNonzeroMagnitude),
                "legacy progress is negative for previous")
            expectEqual(double(next, 129), 1000, "legacy velocity rides on every phase")
            expectEqual(double(next, 130), 1000, "legacy carries velocity on both axes")
            expectEqual(double(previous, 129), -1000, "legacy velocity is signed by direction")
            expect(value(next, 4205) == nil, "the payload is never written as an ordinary field")
        }
        expect(
            fields(.began, .next, augmented: false).allSatisfy { $0.raw != 134 },
            "the legacy path writes no phase alias")
    }

    static func testAugmentedFields() {
        for phase in SpaceGesture.Phase.allCases {
            let next = fields(phase, .next, augmented: true)
            let previous = fields(phase, .previous, augmented: true)
            expectEqual(integer(next, 134), phase.rawValue, "the phase alias mirrors the phase")
            expectEqual(double(next, 138), 3, "the zoom delta is the constant the Dock expects")
            expectEqual(double(next, 125), 0.1, "the swipe starts at a nonzero position")
            expectEqual(double(next, 169), 12_345, "the process alias carries the timestamp")
            // Sign stays consistent with the legacy path; inverting it moves the wrong way.
            expect(double(next, 124)! > 0, "augmented progress is positive for next")
            expect(double(previous, 124)! < 0, "augmented progress is negative for previous")
            expectEqual(
                SpaceGesture.fixed1616(double(next, 124)!), 1,
                "augmented progress survives 16.16 quantization as exactly one step")
            expect(value(next, 130) == nil, "the augmented path writes no Y velocity")
        }
        expect(
            value(fields(.began, .next, augmented: true), 129) == nil,
            "velocity before the last phase would bounce the Space back")
        expect(
            value(fields(.changed, .next, augmented: true), 129) == nil,
            "the changed phase carries no velocity either")
        expectEqual(
            double(fields(.ended, .next, augmented: true), 129), 1000,
            "only the ended phase flings")
        expectEqual(
            double(fields(.ended, .previous, augmented: true), 129), -1000,
            "the fling is signed by direction")
    }

    // MARK: - Payload

    static func testPayloadShape() {
        for phase in [SpaceGesture.Phase.began, .changed] {
            let payload = SpaceGesture.payload(phase: phase, direction: .next, timestamp: 7)
            expectEqual(payload.count, 68, "a \(phase) payload is a header plus a fluid record")
            expectEqual(read(payload, at: 24, as: UInt32.self), 1, "\(phase) reports one event")
        }
        let ended = SpaceGesture.payload(phase: .ended, direction: .next, timestamp: 7)
        expectEqual(ended.count, 96, "the ended payload appends a velocity record")
        expectEqual(read(ended, at: 24, as: UInt32.self), 2, "the ended payload reports two events")
    }

    static func testPayloadValues() {
        let payload = SpaceGesture.payload(phase: .ended, direction: .next, timestamp: 99)
        expectEqual(read(payload, at: 0, as: UInt64.self), 99, "the header carries the timestamp")
        expectEqual(read(payload, at: 8, as: UInt64.self), 0, "the sender id is unset")
        expectEqual(read(payload, at: 20, as: UInt32.self), 0, "there are no trailing attributes")

        expectEqual(read(payload, at: 28, as: UInt32.self), 40, "the fluid record declares its size")
        expectEqual(read(payload, at: 32, as: UInt32.self), 23, "the fluid record is a touch gesture")
        expectEqual(
            read(payload, at: 36, as: UInt32.self), UInt32(SpaceGesture.Phase.ended.rawValue) << 24,
            "the phase rides in the top byte of the record options")
        expectEqual(read(payload, at: 40, as: UInt8.self), 0, "the fluid record sits at depth zero")
        expectEqual(read(payload, at: 44, as: Int32.self), 6_553, "the start position is 0.1 in 16.16")
        expectEqual(read(payload, at: 56, as: UInt32.self), 0, "no swipe mask is claimed")
        expectEqual(read(payload, at: 60, as: UInt16.self), 1, "the record motion is horizontal")
        expectEqual(read(payload, at: 62, as: UInt16.self), 3, "the flavour is the primary dock swipe")
        expectEqual(read(payload, at: 64, as: Int32.self), 1, "progress lands on a single step")

        expectEqual(read(payload, at: 68, as: UInt32.self), 28, "the velocity record declares its size")
        expectEqual(read(payload, at: 72, as: UInt32.self), 9, "the velocity record is a velocity")
        expectEqual(read(payload, at: 80, as: UInt8.self), 1, "the velocity record sits at depth one")
        expectEqual(
            read(payload, at: 84, as: Int32.self), 1000 * 65_536, "the fling velocity is in 16.16")
        expectEqual(read(payload, at: 88, as: Int32.self), 0, "the fling has no vertical component")

        let previous = SpaceGesture.payload(phase: .ended, direction: .previous, timestamp: 99)
        expectEqual(read(previous, at: 64, as: Int32.self), -1, "previous reverses progress")
        expectEqual(
            read(previous, at: 84, as: Int32.self), -1000 * 65_536, "previous reverses the fling")
    }

    static func testRecordHeader() {
        expectEqual(
            SpaceGesture.payloadRecordHeader(payloadCount: 68), [0, 68, 0x10, 0x6D],
            "a 68-byte blob is framed big-endian against field 4205")
        expectEqual(
            SpaceGesture.payloadRecordHeader(payloadCount: 96), [0, 96, 0x10, 0x6D],
            "the framed size tracks the payload")
        expectEqual(
            SpaceGesture.payloadRecordHeader(payloadCount: 300), [1, 44, 0x10, 0x6D],
            "a size past one byte splits across the big-endian pair")
        expectEqual(SpaceGesture.payloadField, 4205, "the payload rides in the raw IOHID field")
        expectEqual(SpaceGesture.dataVersion, [0, 0, 0, 2], "only serialization version 2 is spliced")
    }
}
