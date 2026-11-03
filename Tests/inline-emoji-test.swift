import Foundation

@main
struct InlineEmojiTests {
    static func main() {
        var failures = 0
        func expect(_ condition: Bool, _ description: String) {
            if !condition { print("FAIL: \(description)"); failures += 1 }
        }
        let now = Date(timeIntervalSince1970: 1_000)
        var policy = InlineEmojiPolicy()
        func process(_ input: InlineEmojiPolicy.Input, results: Bool = false) -> InlineEmojiPolicy.Decision {
            policy.process(input, at: now, hasResults: results)
        }

        expect(
            process(.text(":")) == .init(effect: .search(""), consumesKey: false),
            "colon opens without eating input")
        expect(process(.text("smile")).effect == .search("smile"), "typing refines the query")
        expect(process(.move(1), results: true).consumesKey, "visible results own the arrow keys")
        expect(
            process(.accept, results: true) == .init(effect: .insert("smile"), consumesKey: true),
            "Return replaces the query")
        expect(policy.query == nil, "accept ends detection")
        expect(!process(.accept).consumesKey, "ordinary Return passes through")

        for prefix in ["https", "12", "name", ":", "/"] {
            policy.reset()
            _ = process(.text(prefix))
            expect(process(.text(":")).effect != .search(""), "colon after \(prefix) is ordinary text")
        }
        for prefix in [" ", "\n", "(", "["] {
            policy.reset()
            _ = process(.text(prefix))
            expect(
                process(.text(":")).effect == .search(""), "boundary after \(prefix.debugDescription) opens")
        }

        policy.reset()
        _ = process(.text(":"))
        _ = process(.text("hand waving"))
        expect(policy.query == "hand waving", "multiword queries survive spaces")
        expect(process(.deleteBackward).effect == .search("hand wavin"), "backspace edits the search")
        expect(
            process(.escape).consumesKey && policy.query == nil, "Escape dismisses without reaching the app")
        expect(!process(.escape).consumesKey, "Escape without a picker passes through")

        _ = process(.text(":"))
        expect(process(.deleteBackward).effect == .dismiss, "deleting the trigger dismisses")
        _ = process(.text(" "))
        _ = process(.text(":"))
        expect(!process(.accept).consumesKey && policy.query == nil, "no matches leaves Return alone")
        _ = process(.text(":"))
        expect(!process(.move(-1)).consumesKey && policy.query == nil, "no matches leaves arrows alone")

        for input in [InlineEmojiPolicy.Input.reset, .text("/"), .text("\n"), .text(":"), .text("  ")] {
            policy.reset()
            _ = process(.text(":"))
            _ = process(.text("face"))
            expect(
                process(input).effect == .dismiss && policy.query == nil,
                "navigation and punctuation end detection")
        }
        policy.reset()
        _ = process(.text(":"))
        _ = process(.text(String(repeating: "a", count: InlineEmojiPolicy.maximumQueryLength)))
        expect(process(.text("a")).effect == .dismiss, "the buffer has a fixed cap")

        policy.reset()
        _ = process(.text(":"))
        let expired = policy.process(.accept, at: now.addingTimeInterval(16), hasResults: true)
        expect(!expired.consumesKey && policy.query == nil, "expired sessions cannot replace text")
        _ = process(.text(":"))
        expect(process(.text("ねこ")).effect == .search("ねこ"), "non-Latin search text survives")

        print(failures == 0 ? "ALL PASSED" : "\(failures) FAILED")
        exit(failures == 0 ? 0 : 1)
    }
}
