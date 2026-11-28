import Foundation
import Testing

@testable import Tinycast

/// The disguise must be stable, address-shaped, and give a squinting viewer nothing.
struct RedactionTests {
    static let structural = Set("@._-")

    let email = "ashish.kumar@example.com"
    let redacted: String

    init() {
        redacted = RedactedPlaceholder.forValue(email)
    }

    @Test func theSameValueAlwaysWearsTheSameDisguise() {
        #expect(RedactedPlaceholder.forValue(email) == redacted)
    }

    @Test func aDifferentValueGetsADifferentDisguise() {
        #expect(RedactedPlaceholder.forValue("someone.else@example.com") != redacted)
    }

    @Test func lengthIsPreservedSoTheRowDoesNotReflow() {
        #expect(redacted.count == email.count)
    }

    @Test func theAtSignStaysPut() {
        #expect(Self.offsetOfAt(in: redacted) == Self.offsetOfAt(in: email))
    }

    @Test func everyDotKeepsItsPosition() {
        #expect(zip(redacted, email).allSatisfy { ($0 == ".") == ($1 == ".") })
    }

    @Test func hyphensAndUnderscoresPassThrough() {
        #expect(RedactedPlaceholder.forValue("a-b_c@d.e").filter { "-_@.".contains($0) } == "-_@.")
    }

    @Test func theDisguiseIsNotTheValue() {
        #expect(redacted != email)
    }

    /// Not "every character differs": avoiding the real glyph would announce what it is not.
    @Test func theOverwhelmingMajorityOfCharactersMoved() {
        let content = zip(redacted, email).filter { !Self.structural.contains($0.1) }
        let moved = content.filter { $0.0 != $0.1 }.count
        #expect(Double(moved) / Double(content.count) > 0.8)
    }

    @Test func structuralCharactersAreTheOnlyOnesGuaranteedToMatch() {
        #expect(zip(redacted, email).allSatisfy { !Self.structural.contains($1) || $0 == $1 })
    }

    @Test func theAlphabetAvoidsLookAlikeGlyphs() {
        let ambiguous = Set("ilo01")
        #expect(redacted.filter { !Self.structural.contains($0) }.allSatisfy { !ambiguous.contains($0) })
    }

    @Test func anEmptyValueProducesAnEmptyDisguise() {
        #expect(RedactedPlaceholder.forValue("").isEmpty)
    }

    @Test func aValueThatIsOnlyStructureIsReturnedUnchanged() {
        #expect(RedactedPlaceholder.forValue("@.") == "@.")
    }

    /// A disguise that repeats one character would read as obviously fake.
    @Test func theScrambleIsNotASingleRepeatedCharacter() {
        #expect(Set(redacted.filter { !Self.structural.contains($0) }).count > 1)
    }

    private static func offsetOfAt(in text: String) -> Int? {
        text.firstIndex(of: "@").map { text.distance(from: text.startIndex, to: $0) }
    }
}
