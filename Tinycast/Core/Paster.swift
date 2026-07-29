import AppKit
import Carbon.HIToolbox

enum Paster {
    /// Write the item onto the pasteboard and paste it into `previousApp` via a synthetic ⌘V, activating that app so the keystroke lands there. Returns whether content was written (and thus promoted).
    @MainActor @discardableResult
    static func paste(
        _ item: ClipboardItem, store: ClipboardStore, previousApp: NSRunningApplication?
    ) -> Bool {
        guard write(item, store: store) else { return false }
        previousApp?.activate()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            postCommandV()
        }
        return true
    }

    /// Put the item on the pasteboard without pasting; the internal marker keeps our poller from re-capturing it.
    @MainActor @discardableResult
    static func copy(_ item: ClipboardItem, store: ClipboardStore) -> Bool {
        write(item, store: store)
    }

    /// Put a plain string on the pasteboard *without* the internal marker, so a copied calculator answer flows into clipboard history like any other copy.
    @MainActor
    static func copyPlainText(_ text: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.declareTypes([.string], owner: nil)
        pb.setString(text, forType: .string)
    }

    /// Put a PNG on the pasteboard without the internal marker so a camera capture enters clipboard history like a normal copy.
    @MainActor
    static func copyImage(_ png: Data) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.declareTypes([.png], owner: nil)
        pb.setData(png, forType: .png)
    }

    /// String counterpart of `paste(_:store:previousApp:)` — marker-stamped so pasted emoji don't re-enter clipboard history.
    @MainActor
    static func pasteString(_ text: String, previousApp: NSRunningApplication?) {
        writeString(text)
        previousApp?.activate()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            postCommandV()
        }
    }

    /// String counterpart of `copy(_:store:)`.
    @MainActor
    static func copyString(_ text: String) {
        writeString(text)
    }

    /// String counterpart of `pasteInPlace(_:store:into:)` — ⌘V delivered to the target's process, palette stays frontmost.
    @MainActor
    static func pasteStringInPlace(_ text: String, into app: NSRunningApplication?) {
        writeString(text)
        guard let pid = app?.processIdentifier else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            postCommandV(toPid: pid)
        }
    }

    @MainActor
    private static func writeString(_ text: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.declareTypes([.string, ClipboardManager.internalType], owner: nil)
        pb.setString(text, forType: .string)
        pb.setData(Data(), forType: ClipboardManager.internalType)
    }

    /// Paste into `app` *without* activating it (⌘V delivered straight to its process), leaving Tinycast frontmost so the palette stays open. Returns whether content was written (and thus promoted).
    @MainActor @discardableResult
    static func pasteInPlace(
        _ item: ClipboardItem, store: ClipboardStore, into app: NSRunningApplication?
    ) -> Bool {
        guard write(item, store: store) else { return false }
        if let pid = app?.processIdentifier {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                postCommandV(toPid: pid)
            }
        }
        return true
    }

    /// Returns whether content was actually written; if the item's text/image is gone, the pasteboard is left untouched (never cleared to empty) and the caller skips the paste.
    @MainActor @discardableResult
    private static func write(_ item: ClipboardItem, store: ClipboardStore) -> Bool {
        let pb = NSPasteboard.general
        switch item.kind {
        case .text:
            guard let text = item.text else { return false }
            pb.clearContents()
            pb.declareTypes([.string, ClipboardManager.internalType], owner: nil)
            pb.setString(text, forType: .string)
        case .image:
            guard let url = store.imageURL(for: item), let data = try? Data(contentsOf: url) else {
                return false
            }
            pb.clearContents()
            pb.declareTypes([.png, ClipboardManager.internalType], owner: nil)
            pb.setData(data, forType: .png)
        }
        pb.setData(Data(), forType: ClipboardManager.internalType)
        // Whatever lands back on the pasteboard becomes the most recent history entry (Raycast-style); the poller skips marked writes, so this is the only promotion point.
        store.promote(item)
        return true
    }

    /// Synthesize ⌘V — delivered to `pid` alone when given, otherwise through the system tap to whatever is frontmost.
    @MainActor
    private static func postCommandV(toPid pid: pid_t? = nil) {
        guard Permissions.ensureAccessibility() else { return }
        let source = CGEventSource(stateID: .combinedSessionState)
        let v = CGKeyCode(kVK_ANSI_V)
        let down = CGEvent(keyboardEventSource: source, virtualKey: v, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: v, keyDown: false)
        down?.flags = .maskCommand
        up?.flags = .maskCommand
        if let pid {
            down?.postToPid(pid)
            up?.postToPid(pid)
        } else {
            down?.post(tap: .cghidEventTap)
            up?.post(tap: .cghidEventTap)
        }
    }
}
