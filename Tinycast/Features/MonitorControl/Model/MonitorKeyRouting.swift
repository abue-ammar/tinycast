import Foundation

struct MonitorKeyRouting: Sendable {
    struct Display: Sendable {
        let id: UInt32
        let name: String
        let bounds: CGRect
        var values: [MonitorControlKind: MonitorControlValue]

        func contains(_ point: CGPoint) -> Bool {
            point.x >= bounds.origin.x && point.x < bounds.origin.x + bounds.size.width
                && point.y >= bounds.origin.y && point.y < bounds.origin.y + bounds.size.height
        }
    }

    struct Command: Sendable {
        let generation: UInt64
        let displayID: UInt32
        let control: MonitorControlKind
        let value: MonitorControlValue
        let revision: UInt64
        var adjustment: MonitorControlAdjustment
    }

    struct Route: Sendable {
        let generation: UInt64
        let displayID: UInt32?
    }

    var generation: UInt64 = 0
    var displays: [Display] = []
    var audioTarget: UInt32?
    var enabled = false
    var fineAdjustments = true
    var revision: UInt64 = 0
    var held: [Int: Route] = [:]
    var revisions: [UInt32: [MonitorControlKind: UInt64]] = [:]

    mutating func handle(_ key: MonitorMediaKey, point: CGPoint) -> (consume: Bool, command: Command?) {
        if !key.pressed {
            let route = held.removeValue(forKey: key.token)
            return (route?.displayID != nil, nil)
        }
        if held[key.token] == nil {
            let target = enabled && key.supportedModifiers && !key.repeated
                ? displays.first { display in
                    display.values[key.action.control] != nil
                        && (key.action.control == .brightness ? display.contains(point) : audioTarget == display.id)
                }?.id : nil
            held[key.token] = Route(generation: generation, displayID: target)
        }
        guard let route = held[key.token], let id = route.displayID else { return (false, nil) }
        guard enabled, route.generation == generation,
            key.supportedModifiers, !(key.action == .mute && key.repeated),
            key.action.control == .brightness || audioTarget == id,
            let index = displays.firstIndex(where: { $0.id == id }),
            let current = displays[index].values[key.action.control]
        else { return (true, nil) }
        let fine = fineAdjustments != key.fine
        let next = key.action == .mute ? current.toggledMute : current.stepped(up: key.action.up, fine: fine)
        let adjustment: MonitorControlAdjustment = key.action == .mute ? .mute(toggle: true)
            : .step(from: current, to: next, up: key.action.up, fine: fine)
        revision &+= 1
        displays[index].values[key.action.control] = next
        revisions[id, default: [:]][key.action.control] = revision
        return (true, Command(generation: generation, displayID: id, control: key.action.control,
                              value: next, revision: revision, adjustment: adjustment))
    }

    mutating func complete(_ command: Command, value: MonitorControlValue?) -> Bool {
        guard command.generation == generation,
            let index = displays.firstIndex(where: { $0.id == command.displayID }) else { return false }
        guard let value else {
            displays[index].values.removeValue(forKey: command.control)
            return true
        }
        guard revisions[command.displayID]?[command.control] == command.revision else { return false }
        displays[index].values[command.control] = value
        return true
    }
}
