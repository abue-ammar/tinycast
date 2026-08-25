import Foundation

/// The stand-in a redacted value wears until someone asks for the real one. Derived from the value,
/// so a redrawn row never reshuffles into a different disguise, and shaped like it — `@`, `.`, `-`
/// and `_` survive — so an address still reads as an address behind the blur. The scramble is the
/// redaction and the blur only signals it: a blurred real address can be read back off a paused
/// frame, a blurred fake one has nothing to give up. Length survives too, so that much still leaks.
enum RedactedPlaceholder {
    /// No `i`, `l`, `o`, `0` or `1`: a half-blurred glyph should not be identifiable by elimination.
    private static let alphabet = Array("abcdefghjkmnpqrstuvwxyz23456789")

    /// The characters that carry an address's shape rather than its content.
    private static let structural: Set<Character> = ["@", ".", "-", "_"]

    /// Same input, same disguise, every time.
    static func forValue(_ value: String) -> String {
        var state = seed(value)
        return String(
            value.map { character in
                guard !structural.contains(character) else { return character }
                return alphabet[Int(next(&state) % UInt32(alphabet.count))]
            })
    }

    /// FNV-1a over the value's UTF-8 — cheap and stable across launches, and no kind of boundary.
    private static func seed(_ value: String) -> UInt32 {
        var state: UInt32 = 0x811c_9dc5
        for byte in value.utf8 {
            state ^= UInt32(byte)
            state = state &* 0x0100_0193
        }
        return state
    }

    /// One xorshift-multiply round, so neighbouring characters don't walk a visible pattern.
    private static func next(_ state: inout UInt32) -> UInt32 {
        state ^= state >> 13
        state = state &* 0x85eb_ca6b
        state ^= state >> 16
        state = state &* 0xc2b2_ae35
        return state
    }
}
