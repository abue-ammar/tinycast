import AppKit
import Observation
import Carbon.HIToolbox
// `@preconcurrency` downgrades AX diagnostics: the attribute keys are constant C globals.
@preconcurrency import ApplicationServices

enum AIDeliveryOutcome: Equatable {
    case replaced  // AX in-place write
    case pasted  // synthetic ⌘V over the selection
    case copiedToClipboard  // target lost focus; result parked on the clipboard instead
    case failed(String)
}

@MainActor
final class AITextDelivery {
    /// Wired by AppCore to clipboardManager.synchronizeAfterTinycastPasteboardMutation(changeCount:)
    /// so restoring the original clipboard never lands in clipboard history.
    @ObservationIgnored var onPasteboardMutation: ((Int) -> Void)?

    // Duplicated from ClipboardManager.internalType and Paster.tinycastEventTag on purpose:
    // features don't reach into each other, so the raw values are the cross-feature contract.
    fileprivate static let markerType = NSPasteboard.PasteboardType("com.tinycast.internal")
    private static let eventTag: Int64 = 0x54494E59

    func replaceSelection(
        _ result: String, originalSelection: String, in targetApp: NSRunningApplication?
    ) async -> AIDeliveryOutcome {
        if let outcome = replaceUsingAccessibility(result, in: targetApp) { return outcome }
        return await paste(result, originalSelection: originalSelection, in: targetApp)
    }

    /// AX writes move neither focus nor the pasteboard, so they're tried first; nil means the
    /// selection isn't directly writable text and the paste path should take over.
    private func replaceUsingAccessibility(
        _ result: String, in targetApp: NSRunningApplication?
    ) -> AIDeliveryOutcome? {
        guard let targetApp,
            let element = AccessibilityText.focusedElement(in: targetApp),
            isAttributeSettable(kAXSelectedTextAttribute, in: element)
        else { return nil }
        guard
            AXUIElementSetAttributeValue(
                element,
                kAXSelectedTextAttribute as CFString,
                result as CFString) == .success
        else { return nil }
        return .replaced
    }

    /// Rides the real clipboard through a synthetic ⌘V, then puts the snapshot back. Bounded:
    /// a 1s activation poll plus a 150ms settle beat on top of the AX attempt's messaging timeouts.
    private func paste(
        _ result: String, originalSelection: String, in targetApp: NSRunningApplication?
    ) async -> AIDeliveryOutcome {
        guard Permissions.ensureAccessibility() else {
            return .failed("Allow Tinycast to control your Mac in Accessibility settings, then try again.")
        }
        let pasteboard = NSPasteboard.general
        guard let snapshot = Snapshot(pasteboard: pasteboard),
            let writtenItems = snapshot.markedItems(replacingFirstStringWith: result)
        else { return .failed("Could not preserve the clipboard for the paste.") }

        pasteboard.clearContents()
        guard pasteboard.writeObjects(writtenItems) else {
            // The clear already destroyed the user's clipboard, so best effort puts it back.
            pasteboard.writeObjects(snapshot.pasteboardItems())
            return .failed("Could not stage the result on the clipboard.")
        }
        // Ownership mark: any other write between here and the restore means we lost the board.
        let ownedChangeCount = pasteboard.changeCount

        guard await activateAndWait(for: targetApp) else {
            // Never came forward: park the result unmarked so it enters history like any copy.
            pasteboard.clearContents()
            pasteboard.setString(result, forType: .string)
            return .copiedToClipboard
        }

        // The model ran while the user kept working; pasting over a moved selection would corrupt
        // unrelated text, so fail closed to the clipboard instead of guessing.
        if let targetApp,
            !originalSelection.isEmpty,
            let current = AccessibilityText.selection(in: targetApp),
            current != originalSelection
        {
            if pasteboard.changeCount == ownedChangeCount {
                onPasteboardMutation?(restore(snapshot, over: writtenItems[0]))
            }
            return .failed("The selection changed while the transform was running.")
        }

        postCommandV(to: targetApp)
        // One settle beat: the keystroke must reach the target before the clipboard reverts.
        try? await Task.sleep(for: .milliseconds(150))

        guard pasteboard.changeCount == ownedChangeCount else { return .pasted }
        onPasteboardMutation?(restore(snapshot, over: writtenItems[0]))
        return .pasted
    }

    /// 50 × 20ms polls cover the gap between `activate()` returning and the window server actually
    /// switching focus, the same bound SnippetTextInjector uses; a wedged app can't stall delivery.
    private func activateAndWait(for targetApp: NSRunningApplication?) async -> Bool {
        guard let targetApp, !targetApp.isTerminated else { return false }
        targetApp.activate()
        for _ in 0..<50 {
            if targetApp.isActive,
                NSWorkspace.shared.frontmostApplication?.processIdentifier
                    == targetApp.processIdentifier
            {
                return true
            }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return false
    }

    /// Tagged like every Tinycast keystroke so the snippet keyword tap can skip it; the value
    /// matches Paster.tinycastEventTag because features don't import each other.
    private func postCommandV(to targetApp: NSRunningApplication?) {
        let source = CGEventSource(stateID: .combinedSessionState)

        let v = CGKeyCode(kVK_ANSI_V)
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: v, keyDown: true),
            let up = CGEvent(keyboardEventSource: source, virtualKey: v, keyDown: false)
        else { return }

        down.flags = .maskCommand
        up.flags = .maskCommand
        down.setIntegerValueField(.eventSourceUserData, value: Self.eventTag)
        up.setIntegerValueField(.eventSourceUserData, value: Self.eventTag)

        if let targetApp {
            down.postToPid(targetApp.processIdentifier)
            up.postToPid(targetApp.processIdentifier)
        } else {
            down.post(tap: .cghidEventTap)
            up.post(tap: .cghidEventTap)
        }
    }

    /// Swaps the original string back into the item already sitting on the pasteboard — a
    /// clear-and-rewrite would bump the change count and read to history as a brand-new copy.
    /// Returns the count to report, which is what makes the history handshake above succeed.
    private func restore(_ snapshot: Snapshot, over writtenItem: NSPasteboardItem) -> Int {
        if let original = snapshot.firstStringData {
            _ = writtenItem.setData(original, forType: .string)
        } else {
            // The clipboard was empty before us, so emptiness is the original state.
            NSPasteboard.general.clearContents()
        }
        return NSPasteboard.general.changeCount
    }

    private func isAttributeSettable(_ attribute: String, in element: AXUIElement) -> Bool {
        var settable = DarwinBoolean(false)
        AXUIElementIsAttributeSettable(element, attribute as CFString, &settable)
        return settable.boolValue
    }
}

/// Byte-for-byte copy of the pasteboard so the round-trip can put back exactly what was there,
/// images and extra items included. Modeled on Snippets' PasteboardSnapshot.
@MainActor
private struct Snapshot {
    struct Item {
        let values: [(type: NSPasteboard.PasteboardType, data: Data)]
    }

    let items: [Item]

    var firstStringData: Data? {
        items.first?.values.first { $0.type == .string }?.data
    }

    init?(pasteboard: NSPasteboard) {
        let changeCount = pasteboard.changeCount
        var items: [Item] = []
        for pasteboardItem in pasteboard.pasteboardItems ?? [] {
            var values: [(type: NSPasteboard.PasteboardType, data: Data)] = []
            for type in pasteboardItem.types {
                guard let data = pasteboardItem.data(forType: type) else { return nil }
                values.append((type: type, data: data))
            }
            items.append(Item(values: values))
        }
        // A foreign write mid-snapshot would leave us restoring a half-seen clipboard.
        guard pasteboard.changeCount == changeCount else { return nil }
        self.items = items
    }

    func pasteboardItems() -> [NSPasteboardItem] {
        items.map { item in
            let pasteboardItem = NSPasteboardItem()
            for value in item.values {
                _ = pasteboardItem.setData(value.data, forType: value.type)
            }
            return pasteboardItem
        }
    }

    /// The marked item carries only the plain result — stale rich data from the original copy
    /// would paste the old text right back — while later items ride along untouched.
    func markedItems(replacingFirstStringWith text: String) -> [NSPasteboardItem]? {
        let first = NSPasteboardItem()
        guard first.setString(text, forType: .string),
            first.setData(Data(), forType: AITextDelivery.markerType)
        else { return nil }
        if items.isEmpty { return [first] }

        var result = [first]
        result.reserveCapacity(items.count)
        for item in items.dropFirst() {
            let pbItem = NSPasteboardItem()
            for value in item.values {
                guard pbItem.setData(value.data, forType: value.type) else { return nil }
            }
            result.append(pbItem)
        }
        return result
    }
}
