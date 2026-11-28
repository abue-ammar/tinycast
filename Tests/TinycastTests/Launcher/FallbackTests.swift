import Foundation
import Testing

@testable import Tinycast

@MainActor
struct FallbackTests {
    @Test(arguments: Fallback.Builtin.allCases)
    func builtinIdentityUsesTheCommandID(_ builtin: Fallback.Builtin) throws {
        let fallback = Fallback.builtin(builtin)
        #expect(fallback.id == builtin.command.rawValue)
        let restored = try #require(Fallback(id: fallback.id))
        #expect(restored == fallback)
    }

    @Test func quicklinkIdentityUsesTheEntryID() throws {
        let id = UUID()
        let fallback = Fallback.quicklink(id)
        #expect(fallback.id == Quicklink.entryIDPrefix + id.uuidString.lowercased())
        let restored = try #require(Fallback(id: fallback.id))
        #expect(restored == fallback)
    }

    @Test func builtinIDsAreDistinct() {
        let ids = Fallback.Builtin.allCases.map { Fallback.builtin($0).id }
        #expect(Set(ids).count == Fallback.Builtin.allCases.count)
    }

    @Test(arguments: [CommandID.about.rawValue, "banana"])
    func unrelatedIDsCannotRestoreAFallback(_ id: String) {
        #expect(Fallback(id: id) == nil)
    }

    @Test func aBareUUIDCannotRestoreAFallback() {
        #expect(Fallback(id: UUID().uuidString) == nil)
    }

    @Test func offeredOrderIsTheDefaultAndStoredOrderOverridesIt() {
        let ai = Fallback.builtin(.quickAI)
        let files = Fallback.builtin(.searchFiles)
        let shell = Fallback.builtin(.runShellCommand)

        #expect(Fallback.ordered([ai, files, shell], by: []) == [ai, files, shell])
        #expect(Fallback.ordered([ai, files, shell], by: [shell.id, ai.id, files.id]) == [shell, ai, files])
    }

    @Test func newFallbacksFollowStoredOnesAndRemovedOnesAreSkipped() {
        let ai = Fallback.builtin(.quickAI)
        let files = Fallback.builtin(.searchFiles)
        let link = Fallback.quicklink(UUID())

        #expect(Fallback.ordered([ai, link, files], by: [files.id, ai.id]) == [files, ai, link])
        #expect(Fallback.ordered([ai, files], by: [link.id, files.id, ai.id]) == [files, ai])
        #expect(Fallback.ordered([], by: [ai.id]).isEmpty)
    }

    @Test(arguments: ["todo", "https://github.com/vgnshiyer/py-apple-books.git"])
    func defaultHeaderKeepsTheWholeQuery(_ query: String) {
        #expect(Fallback.sectionTitle(query: query) == "Use “\(query)” with…")
    }

    @Test func headerKeepsTheWholeQueryAtTheLimit() {
        let query = String(repeating: "b", count: 20)
        #expect(Fallback.sectionTitle(query: query, limit: 20) == "Use “\(query)” with…")
    }

    @Test func headerElidesTheMiddleOfALongQuery() {
        let query = String(repeating: "a", count: 200)
        let title = Fallback.sectionTitle(query: query, limit: 20)
        #expect(title.hasSuffix("” with…"))
        #expect(title.contains("…a"))
        #expect(title.count <= 20 + 13)
    }

    @Test func eachFallbackHasADistinctAction() {
        let verbs = Fallback.Builtin.allCases.map { Fallback.builtin($0).openVerb }
            + [Fallback.quicklink(UUID()).openVerb]
        #expect(verbs.allSatisfy { !$0.isEmpty })
        #expect(Set(verbs).count == verbs.count)
    }
}
