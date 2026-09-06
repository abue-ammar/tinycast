import CoreGraphics
import Foundation

/// Switches Space with a synthetic Dock swipe, so macOS skips its sliding transition.
@MainActor
final class SpaceSwitcher {
    /// The running OS decides whether the payload is required, so this cannot be `#available`.
    private nonisolated static let augmentsEvents = ProcessInfo.processInfo.isOperatingSystemAtLeast(
        OperatingSystemVersion(majorVersion: 27, minorVersion: 0, patchVersion: 0))

    private var gesture: Task<Void, Never>?

    /// A second gesture overlapping the first makes the Dock move two Spaces, so it is dropped.
    func perform(_ direction: SpaceDirection) {
        guard gesture == nil, Permissions.ensureAccessibility() else { return }
        gesture = Task {
            await Self.post(direction)
            gesture = nil
        }
    }

    private nonisolated static func post(_ direction: SpaceDirection) async {
        for phase in SpaceGesture.Phase.allCases {
            guard let event = event(phase: phase, direction: direction) else { return }
            event.post(tap: .cgSessionEventTap)
            guard augmentsEvents, phase != .ended else { continue }
            try? await Task.sleep(for: SpaceGesture.phaseDelay)
        }
    }

    private nonisolated static func event(
        phase: SpaceGesture.Phase, direction: SpaceDirection
    ) -> CGEvent? {
        guard let event = CGEvent(source: nil) else { return nil }
        // A freshly created event carries no timestamp, which the payload cannot be built without.
        let timestamp = mach_absolute_time()
        let fields = SpaceGesture.fields(
            phase: phase, direction: direction, augmented: augmentsEvents, timestamp: timestamp)
        for field in fields {
            guard let key = CGEventField(rawValue: field.raw) else { continue }
            switch field.value {
            case .integer(let value): event.setIntegerValueField(key, value: value)
            case .double(let value): event.setDoubleValueField(key, value: value)
            }
        }
        guard augmentsEvents else { return event }
        let payload = SpaceGesture.payload(
            phase: phase, direction: direction, timestamp: timestamp)
        return augmented(event, payload: payload)
    }

    /// No setter reaches field 4205, so the payload is spliced into the serialized event instead.
    private nonisolated static func augmented(_ event: CGEvent, payload: Data) -> CGEvent? {
        guard var bytes = event.__data(allocator: nil) as Data?,
            bytes.starts(with: SpaceGesture.dataVersion)
        else { return nil }
        bytes.append(contentsOf: SpaceGesture.payloadRecordHeader(payloadCount: payload.count))
        bytes.append(payload)
        return CGEvent(withDataAllocator: nil, data: bytes as CFData)
    }
}
