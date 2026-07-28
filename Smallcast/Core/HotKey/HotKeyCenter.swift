import Carbon.HIToolbox

/// C entry point for the Carbon handler: the owning `HotKeyCenter` rides in `userData`, and since Carbon dispatches on the main thread the `EventRef` is decoded to a plain `EventHotKeyID` before `assumeIsolated` crosses into actor code.
private func hotKeyCarbonEventHandler(
    _: EventHandlerCallRef?, event: EventRef?, userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let event, let userData else { return OSStatus(eventNotHandledErr) }
    var hotKeyID = EventHotKeyID()
    let error = GetEventParameter(
        event,
        UInt32(kEventParamDirectObject),
        UInt32(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hotKeyID
    )
    guard error == noErr else { return error }
    let center = Unmanaged<HotKeyCenter>.fromOpaque(userData).takeUnretainedValue()
    return MainActor.assumeIsolated { center.handle(hotKeyID) }
}

/// The Carbon layer only: turns `KeyShortcut`s into system-wide `RegisterEventHotKey` registrations routed to closures (which shortcuts exist is `HotKeyManager`'s business).
@MainActor
final class HotKeyCenter {
    private struct Entry {
        let shortcut: KeyShortcut
        let onKeyDown: () -> Void
        let carbonID: UInt32
        var ref: EventHotKeyRef?
    }

    /// Live registrations keyed by the caller's stable id, plus the reverse lookup the Carbon callback needs (it only gets the numeric `EventHotKeyID`).
    private var entries: [String: Entry] = [:]
    private var idToKey: [UInt32: String] = [:]
    private var nextCarbonID: UInt32 = 0
    private var eventHandler: EventHandlerRef?
    private let signature: OSType = 0x5459_4354  // FourCC "TYCT"

    /// While `true` every hotkey is soft-unregistered (entries stay, system registrations go), so a recorder can capture combos without triggering them.
    var isPaused = false {
        didSet {
            guard isPaused != oldValue else { return }
            for key in entries.keys {
                if isPaused { deactivate(key) } else { activate(key) }
            }
        }
    }

    /// Registers (or re-registers) `shortcut` under `id`, dropping any previous registration first so changing a binding never leaks the old combo.
    func register(id: String, shortcut: KeyShortcut, onKeyDown: @escaping () -> Void) {
        unregister(id: id)
        nextCarbonID += 1
        entries[id] = Entry(
            shortcut: shortcut, onKeyDown: onKeyDown, carbonID: nextCarbonID, ref: nil)
        idToKey[nextCarbonID] = id
        if !isPaused { activate(id) }
    }

    func unregister(id: String) {
        guard let entry = entries.removeValue(forKey: id) else { return }
        if let ref = entry.ref { UnregisterEventHotKey(ref) }
        idToKey.removeValue(forKey: entry.carbonID)
    }

    private func activate(_ id: String) {
        guard var entry = entries[id], entry.ref == nil else { return }
        installEventHandlerIfNeeded()
        var ref: EventHotKeyRef?
        let error = RegisterEventHotKey(
            UInt32(entry.shortcut.carbonKeyCode),
            UInt32(entry.shortcut.carbonModifiers),
            EventHotKeyID(signature: signature, id: entry.carbonID),
            GetEventDispatcherTarget(),
            0,
            &ref
        )
        // Registration can fail if another app owns the combo system-wide; the binding stays visible in settings but doesn't fire — same as the old package.
        guard error == noErr, let ref else {
            NSLog("Smallcast: could not register hotkey for %@ (OSStatus %d)", id, error)
            return
        }
        entry.ref = ref
        entries[id] = entry
    }

    private func deactivate(_ id: String) {
        guard var entry = entries[id], let ref = entry.ref else { return }
        UnregisterEventHotKey(ref)
        entry.ref = nil
        entries[id] = entry
    }

    private func installEventHandlerIfNeeded() {
        guard eventHandler == nil, let dispatcher = GetEventDispatcherTarget() else { return }
        var eventTypes = [
            EventTypeSpec(
                eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        ]
        InstallEventHandler(
            dispatcher,
            hotKeyCarbonEventHandler,
            eventTypes.count,
            &eventTypes,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandler
        )
    }

    fileprivate func handle(_ hotKeyID: EventHotKeyID) -> OSStatus {
        guard
            hotKeyID.signature == signature,
            let key = idToKey[hotKeyID.id],
            let entry = entries[key]
        else { return OSStatus(eventNotHandledErr) }
        entry.onKeyDown()
        return noErr
    }
}
