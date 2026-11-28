import Foundation
import Testing

@testable import Tinycast

struct AppleShortcutTests {
    let volume: UUID
    let pdf: UUID
    let recipes: UUID

    init() throws {
        volume = try #require(UUID(uuidString: "97A1DDFA-76F3-4872-A672-25D5F35B7882"))
        pdf = try #require(UUID(uuidString: "B63D79CE-D540-4E8C-B5E4-B3BF5FDD1897"))
        recipes = try #require(UUID(uuidString: "DCA44E1D-F062-424D-BA7C-FA91DBFE33FF"))
    }

    private var listed: [AppleShortcut] {
        AppleShortcut.parseList(
            """
            Set Volume to 50% (\(volume.uuidString))
            Summarize PDF (\(pdf.uuidString))
            Leftover Recipes (\(recipes.uuidString))

            """)
    }

    @Test func listedShortcutsSortByNameWithTheUUIDRemoved() throws {
        #expect(listed.count == 3)
        #expect(listed.map(\.id) == [recipes, volume, pdf])
        let first = try #require(listed.first)
        #expect(first.name == "Leftover Recipes")
    }

    @Test func parenthesesInsideTheNameSurviveParsing() throws {
        let items = AppleShortcut.parseList("Log (Work) Hours (\(volume.uuidString))")
        let shortcut = try #require(items.first)
        #expect(shortcut.name == "Log (Work) Hours")
        #expect(shortcut.id == volume)
    }

    @Test func malformedRowsAreIgnoredAndTheFirstValidNameWins() throws {
        let items = AppleShortcut.parseList(
            """
            Error: something went wrong
            Broken (not-a-uuid)
            (\(pdf.uuidString))
            Summarize PDF (\(pdf.uuidString))
            Summarize PDF again (\(pdf.uuidString))
            """)
        #expect(items.count == 1)
        let first = try #require(items.first)
        #expect(first.name == "Summarize PDF")
    }

    @Test func emptyOutputHasNoShortcuts() {
        #expect(AppleShortcut.parseList("").isEmpty)
    }

    @Test func aListingCanUseCRLF() {
        #expect(AppleShortcut.parseList("A (\(pdf.uuidString))\r\nB (\(volume.uuidString))\r\n").count == 2)
    }

    @Test func aSuccessfulListingIdentifiesDeletedShortcutsInPreferencesAndBindings() throws {
        let gone = try #require(UUID(uuidString: "0F6E3C1A-2B4D-4E5F-8A9B-1C2D3E4F5A6B"))
        let unbound = try #require(UUID(uuidString: "5A6B7C8D-9E0F-4A1B-8C2D-3E4F5A6B7C8D"))
        let stored = [
            AppleShortcut.entryID(for: volume), AppleShortcut.entryID(for: gone),
            "quicklink:\(gone.uuidString.lowercased())", "com.apple.Safari", "apple-shortcut:nope"
        ]
        #expect(
            AppleShortcut.staleIDs(referencedBy: stored, bound: [pdf, unbound], live: listed) == [
                gone, unbound
            ])
        #expect(AppleShortcut.staleIDs(referencedBy: stored, bound: [pdf], live: []).isEmpty)
        #expect(AppleShortcut.staleIDs(referencedBy: ["com.apple.Safari"], bound: [], live: listed).isEmpty)
    }

    @Test func onlyAWellFormedShortcutEntryIDResolves() throws {
        let shortcut = AppleShortcut(id: recipes, name: "Leftover Recipes")
        let restored = try #require(AppleShortcut.id(fromEntryID: shortcut.entryID))
        #expect(restored == recipes)
        #expect(AppleShortcut.id(fromEntryID: "quicklink:\(recipes)") == nil)
        #expect(AppleShortcut.id(fromEntryID: "apple-shortcut:nope") == nil)
    }
}
