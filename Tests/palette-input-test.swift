import AppKit
import Carbon.HIToolbox
import SwiftUI

@main
@MainActor
struct PaletteInputTests {
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

    final class InputContext: NSTextInputContext {
        var events: [NSEvent] = []
        var consumesEvent = true
        var endsComposition = false

        override func handleEvent(_ event: NSEvent) -> Bool {
            events.append(event)
            if consumesEvent, endsComposition { client.unmarkText() }
            return consumesEvent
        }
    }

    final class Editor: NSTextView {
        lazy var context = InputContext(client: self)
        var deliveredEvents: [NSEvent] = []

        override var inputContext: NSTextInputContext? { context }

        override func keyDown(with event: NSEvent) {
            deliveredEvents.append(event)
        }

        func beginComposition() {
            setMarkedText(
                "にほん", selectedRange: NSRange(location: 3, length: 0),
                replacementRange: NSRange(location: NSNotFound, length: 0))
        }
    }

    static func key(_ code: Int, _ characters: String, modifiers: NSEvent.ModifierFlags = []) -> NSEvent {
        NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: 0,
            windowNumber: 0, context: nil, characters: characters,
            charactersIgnoringModifiers: characters, isARepeat: false, keyCode: UInt16(code))!
    }

    static func main() {
        _ = NSApplication.shared
        let panel = PalettePanel(rootView: EmptyView())
        let state = PaletteState()
        panel.paletteState = state
        let editor = Editor(frame: NSRect(x: 0, y: 0, width: 200, height: 30))
        panel.contentView?.addSubview(editor)
        expect(panel.makeFirstResponder(editor), "the editor takes focus")

        var paletteActions = 0
        panel.onEscape = { paletteActions += 1; return true }
        panel.onBareBackspace = { paletteActions += 1; return true }
        panel.onCommandShortcut = { _ in paletteActions += 1; return true }
        panel.onHeaderFieldBoundaryArrow = { _ in paletteActions += 1; return true }

        let candidateKeys = [
            key(kVK_Tab, "\t"), key(kVK_Tab, "\u{19}", modifiers: .shift),
            key(kVK_UpArrow, "\u{F700}"), key(kVK_DownArrow, "\u{F701}"),
            key(kVK_LeftArrow, "\u{F702}"), key(kVK_RightArrow, "\u{F703}"),
            key(kVK_Return, "\r"), key(kVK_ANSI_KeypadEnter, "\u{3}"),
            key(kVK_Escape, "\u{1B}"), key(kVK_Delete, "\u{7F}"), key(kVK_Space, " "),
            key(kVK_ANSI_N, "n", modifiers: .control),
            key(kVK_ANSI_P, "p", modifiers: .control),
            key(kVK_ANSI_F, "f", modifiers: .control),
            key(kVK_ANSI_B, "b", modifiers: .control)
        ]
        for event in candidateKeys {
            editor.beginComposition()
            expect(editor.hasMarkedText(), "marked text is present before candidate navigation")
            let deliveredCount = editor.context.events.count
            panel.sendEvent(event)
            expect(editor.context.events.count == deliveredCount + 1, "the IME gets one candidate key")
            expect(editor.context.events.last === event, "the IME gets the original event, without rewriting")
            expect(paletteActions == 0, "candidate navigation triggers no panel action")
            expect(editor.deliveredEvents.isEmpty, "a consumed key never reaches ordinary dispatch")
        }

        editor.context.endsComposition = true
        for event in [key(kVK_Return, "\r"), key(kVK_Escape, "\u{1B}")] {
            editor.beginComposition()
            panel.sendEvent(event)
            expect(!editor.hasMarkedText(), "the IME can end composition during dispatch")
            expect(paletteActions == 0, "ending composition does not replay the key as a palette action")
            expect(editor.deliveredEvents.isEmpty, "the commit key is not delivered twice")
        }

        let consumedCount = editor.context.events.count
        panel.sendEvent(key(kVK_Escape, "\u{1B}"))
        expect(paletteActions == 1, "Escape resumes its palette action after composition")
        let tab = key(kVK_Tab, "\t")
        panel.sendEvent(tab)
        expect(editor.context.events.count == consumedCount, "unmarked input skips IME priority routing")
        expect(editor.deliveredEvents.last === tab, "Tab resumes ordinary dispatch after composition")

        editor.beginComposition()
        editor.context.consumesEvent = false
        let command = key(kVK_ANSI_K, "k", modifiers: .command)
        panel.sendEvent(command)
        expect(editor.context.events.last === command, "the IME has first refusal of a command chord")
        expect(paletteActions == 2, "an unconsumed command retains its palette action")

        editor.unmarkText()
        expect(panel.makeFirstResponder(nil), "focus can leave the editor")
        panel.sendEvent(key(kVK_Escape, "\u{1B}"))
        expect(paletteActions == 3, "panel actions still work without a text input client")
        panel.close()

        print("\(passes) passed, \(failures) failed")
        if failures > 0 { exit(1) }
    }
}
