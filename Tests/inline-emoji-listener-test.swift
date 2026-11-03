import AppKit
import Carbon.HIToolbox

@main
struct InlineEmojiListenerTests {
    static func main() async throws {
        var failures = 0
        func expect(_ condition: Bool, _ description: String) {
            if !condition { print("FAIL: \(description)"); failures += 1 }
        }
        let (stream, continuation) = AsyncStream<InlineEmojiListener.Message>.makeStream()
        let session = InlineEmojiListener.Session(
            continuation: continuation, secureEventInputEnabled: { false })
        var messages = stream.makeAsyncIterator()

        func key(_ code: Int, text: String = "", flags: CGEventFlags = []) throws -> CGEvent {
            guard let event = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(code), keyDown: true)
            else { throw Failure.noEvent }
            var characters = Array(text.utf16)
            event.keyboardSetUnicodeString(stringLength: characters.count, unicodeString: &characters)
            event.flags = flags
            return event
        }

        let colon = try key(kVK_ANSI_Semicolon, text: ":", flags: .maskShift)
        expect(session.handle(.keyDown, colon) != nil, "the original colon reaches the editor")
        guard let opened = await messages.next() else { throw Failure.noMessage }
        expect(opened.effect == .search(""), "the UI receives an empty search")

        let escape = try key(kVK_Escape)
        expect(session.handle(.keyDown, escape) != nil, "Escape is free until a picker is presented")
        _ = await messages.next()
        _ = session.handle(.keyDown, colon)
        guard let presented = await messages.next() else { throw Failure.noMessage }
        session.setPanelBounds(CGRect(x: 10, y: 10, width: 100, height: 100))
        session.setHasResults(true, version: presented.version)

        let down = try key(kVK_DownArrow)
        expect(session.handle(.keyDown, down) == nil, "the picker consumes navigation before the editor")
        guard let moved = await messages.next() else { throw Failure.noMessage }
        expect(moved.effect == .move(1), "navigation is delivered in order")
        expect(session.handle(.keyUp, down) == nil, "consumed key presses also consume their releases")

        let accept = try key(kVK_Return)
        expect(session.handle(.keyDown, accept) == nil, "accept does not insert a newline")
        guard let insertion = await messages.next() else { throw Failure.noMessage }
        expect(insertion.effect == .insert(""), "accept identifies the shortcode to replace")
        session.finishSelection(version: insertion.version)
        accept.setIntegerValueField(.keyboardEventAutorepeat, value: 1)
        expect(session.handle(.keyDown, accept) == nil, "holding Return cannot insert extra newlines")
        expect(session.isCurrent(insertion.version), "a swallowed repeat does not cancel delivery")
        expect(session.handle(.keyDown, down) != nil, "arrows after acceptance return to the editor")
        expect(!session.isCurrent(insertion.version), "new caret movement cancels pending insertion")

        _ = session.handle(.keyDown, colon)
        guard let next = await messages.next() else { throw Failure.noMessage }
        session.setPanelBounds(CGRect(x: 10, y: 10, width: 100, height: 100))
        guard
            let click = CGEvent(
                mouseEventSource: nil, mouseType: .leftMouseDown,
                mouseCursorPosition: CGPoint(x: 20, y: 20), mouseButton: .left)
        else { throw Failure.noEvent }
        _ = session.handle(.leftMouseDown, click)
        expect(session.isCurrent(next.version), "a click on the picker can still select a result")
        click.location = CGPoint(x: 200, y: 200)
        _ = session.handle(.leftMouseDown, click)
        guard let dismissed = await messages.next() else { throw Failure.noMessage }
        expect(
            dismissed.effect == .dismiss && !session.isCurrent(next.version),
            "outside clicks invalidate the target")

        colon.setIntegerValueField(.eventSourceUserData, value: Paster.tinycastEventTag)
        _ = session.handle(.keyDown, colon)
        expect(session.isCurrent(dismissed.version), "synthetic typing never opens or cancels the picker")

        let (_, otherContinuation) = AsyncStream<InlineEmojiListener.Message>.makeStream()
        let other = InlineEmojiListener.Session(
            continuation: otherContinuation, secureEventInputEnabled: { false })
        expect(!other.isCurrent(dismissed.version), "re-enabling cannot revive a previous session's delivery")
        let (secureStream, secureContinuation) = AsyncStream<InlineEmojiListener.Message>.makeStream()
        let secure = InlineEmojiListener.Session(
            continuation: secureContinuation, secureEventInputEnabled: { true })
        var secureMessages = secureStream.makeAsyncIterator()
        colon.setIntegerValueField(.eventSourceUserData, value: 0)
        expect(secure.handle(.keyDown, colon) != nil, "Secure Input keeps all typing with the editor")
        let secureMessage = await secureMessages.next()
        expect(secureMessage?.effect == .dismiss, "Secure Input never starts a search")
        session.setSuspended(true)
        expect(session.isSuspended && !session.isCurrent(dismissed.version), "sleep invalidates pending work")
        session.finish()
        other.finish()
        secure.finish()

        print(failures == 0 ? "ALL PASSED" : "\(failures) FAILED")
        exit(failures == 0 ? 0 : 1)
    }

    private enum Failure: Error {
        case noEvent
        case noMessage
    }
}

enum Permissions {
    static func isAccessibilityTrusted() -> Bool { false }
}

enum Paster {
    static let tinycastEventTag: Int64 = 0x54494E59
}
