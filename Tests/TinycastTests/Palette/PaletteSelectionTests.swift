import Foundation
import Testing

@testable import Tinycast

struct PaletteSelectionTests {
    /// A screen's row order, named for the screen it models.
    struct Shape: CustomTestStringConvertible, Sendable {
        let testDescription: String
        var hasCalculator = false
        let counts: [Int]

        var index: PaletteRowIndex { PaletteRowIndex(hasCalculator: hasCalculator, sectionCounts: counts) }
    }

    static let single = Shape(testDescription: "one section", counts: [3])
    static let withCalculator = Shape(
        testDescription: "one section with the card", hasCalculator: true, counts: [3])
    static let sections = Shape(testDescription: "three sections", counts: [2, 1, 3])
    static let gapped = Shape(testDescription: "an empty middle section", counts: [2, 0, 2])
    static let launcher = Shape(
        testDescription: "the launcher with the card", hasCalculator: true, counts: [2, 1, 3])

    /// Favourites, then one section per kind in `AppIndex` slice order.
    static let launcherSections = Shape(
        testDescription: "the empty-query launcher", counts: [3, 12, 5, 2, 4, 6, 8, 1, 7])
    static let launcherNoFavorites = Shape(
        testDescription: "the launcher without favourites", counts: [0, 12, 5, 2, 4, 6, 8, 1, 7])
    static let launcherHidden = Shape(
        testDescription: "the launcher with hidden categories", counts: [3, 12, 0, 2, 0, 6, 0, 1, 7])
    static let launcherQuery = Shape(
        testDescription: "a typed launcher query", hasCalculator: true, counts: [9])
    static let historyCard = Shape(
        testDescription: "calculator history with the card", hasCalculator: true, counts: [3, 2])

    static let namedShapes = [
        single, withCalculator, sections, gapped, launcher, launcherSections, launcherNoFavorites,
        launcherHidden,
        launcherQuery, historyCard,
        Shape(testDescription: "the uninstall screen", counts: [4]),
        Shape(testDescription: "an argument's choices", counts: [3]),
        Shape(testDescription: "the clipboard", counts: [2, 5, 3]),
        Shape(testDescription: "calculator history without the card", counts: [3, 2]),
        Shape(testDescription: "the emoji grid", counts: [8, 20, 5])
    ]

    /// Each of the launcher's nine sections alone, with and without the card.
    static let eachSectionAlone = [false, true].flatMap { hasCalculator in
        (0..<9).map { section in
            Shape(
                testDescription: "section \(section) alone, card \(hasCalculator)",
                hasCalculator: hasCalculator,
                counts: (0..<9).map { $0 == section ? 3 : 0 })
        }
    }

    /// Each of the launcher's nine sections hidden, with and without the card.
    static let eachSectionHidden = [false, true].flatMap { hasCalculator in
        (0..<9).map { section in
            Shape(
                testDescription: "section \(section) hidden, card \(hasCalculator)",
                hasCalculator: hasCalculator,
                counts: (0..<9).map { $0 == section ? 0 : 2 })
        }
    }

    /// Every three-section shape of up to three rows each, empty sections included.
    static let smallShapes = [false, true].flatMap { hasCalculator in
        (0...3).flatMap { a in
            (0...3).flatMap { b in
                (0...3).map { c in
                    Shape(
                        testDescription: "[\(a), \(b), \(c)], card \(hasCalculator)",
                        hasCalculator: hasCalculator,
                        counts: [a, b, c])
                }
            }
        }
    }

    // MARK: Empty screens

    @Test func anEmptyScreenResolvesNothing() {
        let index = PaletteRowIndex(sectionCounts: [])
        #expect(index.count == 0)
        #expect(index.row(at: 0) == nil)
        #expect(index.index(section: 0, offset: 0) == nil)
    }

    @Test(arguments: [0, 7])
    func anEmptyScreenClampsToZero(_ selection: Int) {
        #expect(PaletteRowIndex(sectionCounts: []).clamped(selection) == 0)
    }

    @Test func sectionsThatAreAllEmptyAreStillAnEmptyScreen() {
        let index = PaletteRowIndex(sectionCounts: [0, 0, 0])
        #expect(index.count == 0)
        #expect(index.row(at: 0) == nil)
    }

    // MARK: One section

    @Test func eachResultOfOneSectionHasItsOwnIndex() {
        let index = Self.single.index
        #expect(index.count == 3)
        #expect(index.row(at: 0) == .element(section: 0, offset: 0))
        #expect(index.row(at: 1) == .element(section: 0, offset: 1))
        #expect(index.row(at: 2) == .element(section: 0, offset: 2))
    }

    @Test(arguments: [3, -1])
    func anIndexOutsideOneSectionResolvesToNothing(_ flat: Int) {
        #expect(Self.single.index.row(at: flat) == nil)
    }

    // MARK: The calculator card

    @Test func theCardTakesIndexZeroAndShiftsEveryResult() {
        let index = Self.withCalculator.index
        #expect(index.count == 4)
        #expect(index.row(at: 0) == .calculator)
        #expect(index.row(at: 1) == .element(section: 0, offset: 0))
        #expect(index.row(at: 3) == .element(section: 0, offset: 2))
        #expect(index.row(at: 4) == nil)
        #expect(index.index(section: 0, offset: 0) == 1)
    }

    @Test func aLoneCardIsTheWholeList() {
        let index = PaletteRowIndex(hasCalculator: true, sectionCounts: [])
        #expect(index.count == 1)
        #expect(index.row(at: 0) == .calculator)
        #expect(index.clamped(9) == 0)
    }

    // MARK: Sections

    /// Headers are not selectable, so no index is spent on them.
    @Test func crossingASectionSpendsNoIndexOnItsHeader() {
        let index = Self.sections.index
        #expect(index.count == 6)
        #expect(index.row(at: 1) == .element(section: 0, offset: 1))
        #expect(index.row(at: 2) == .element(section: 1, offset: 0))
        #expect(
            index.row(at: 3) == .element(section: 2, offset: 0), "a one-row section is crossed in one step")
        #expect(index.row(at: 5) == .element(section: 2, offset: 2))
        #expect(index.row(at: 6) == nil)
    }

    @Test func anEmptySectionIsSteppedOverNotLandedIn() {
        let index = Self.gapped.index
        #expect(index.count == 4)
        #expect(index.row(at: 2) == .element(section: 2, offset: 0))
        #expect(index.index(section: 1, offset: 0) == nil)
    }

    @Test(arguments: [(3, 0), (-1, 0), (0, 2), (0, -1)])
    func inversionOutOfBoundsNeverInventsAnIndex(_ section: Int, _ offset: Int) {
        #expect(Self.sections.index.index(section: section, offset: offset) == nil)
    }

    // MARK: The launcher

    @Test func aSectionCrossingAccountsForTheCard() {
        let index = Self.launcher.index
        #expect(index.count == 7)
        #expect(index.row(at: 0) == .calculator)
        #expect(index.row(at: 3) == .element(section: 1, offset: 0))
        #expect(index.index(section: 2, offset: 2) == 6)
    }

    @Test func theEmptyQueryLauncherIndexesEveryRowButNoHeader() {
        let index = Self.launcherSections.index
        #expect(index.sectionCounts.count == 9)
        #expect(index.count == 48)
        #expect(
            index.row(at: 0) == .element(section: 0, offset: 0), "a pinned favourite leads the whole list")
        #expect(index.row(at: 2) == .element(section: 0, offset: 2))
        #expect(
            index.row(at: 3) == .element(section: 1, offset: 0), "Applications begins where Favorites ends")
        #expect(index.index(section: 8, offset: 6) == 47)
        #expect(index.index(section: 9, offset: 0) == nil)
    }

    @Test func withoutFavouritesApplicationsLeadsAndLaterRowsMoveUp() {
        let index = Self.launcherNoFavorites.index
        #expect(index.row(at: 0) == .element(section: 1, offset: 0))
        #expect(index.index(section: 8, offset: 6) == 44)
    }

    @Test func aHiddenCategoryDropsItsWholeSection() {
        let index = Self.launcherHidden.index
        #expect(index.count == 31)
        #expect(
            index.row(at: 15) == .element(section: 3, offset: 0), "Quicklinks follows Applications directly")
    }

    @Test func aTypedQueryIsOneListLedByTheCard() {
        let index = Self.launcherQuery.index
        #expect(index.count == 10)
        #expect(index.row(at: 0) == .calculator)
        #expect(index.row(at: 1) == .element(section: 0, offset: 0))
        #expect(index.index(section: 0, offset: 8) == 9)
    }

    /// ↵, ⌘↵ and ⌃⇧Q in the launcher and ⌘⌫ in history resolve through this index.
    @Test(arguments: [launcherQuery, historyCard])
    func onlyIndexZeroIsEverTheCard(_ shape: Shape) {
        let index = shape.index
        for flat in 0..<index.count {
            #expect((index.row(at: flat) == .calculator) == (flat == 0), "index \(flat)")
        }
    }

    @Test func aCardWithNoRowsIsTheWholeList() {
        let index = PaletteRowIndex(hasCalculator: true, sectionCounts: [0])
        #expect(index.count == 1)
        #expect(index.row(at: 0) == .calculator)
        #expect(index.row(at: 1) == nil)
    }

    @Test(arguments: [6, 4])
    func aStaleSelectionClampsBackOntoALoneCard(_ selection: Int) {
        #expect(PaletteRowIndex(hasCalculator: true, sectionCounts: [0]).clamped(selection) == 0)
    }

    @Test(arguments: eachSectionAlone)
    func aSectionAloneStartsAtTheHeadOfTheList(_ shape: Shape) throws {
        let section = try #require(shape.counts.firstIndex(of: 3))
        #expect(shape.index.index(section: section, offset: 0) == (shape.hasCalculator ? 1 : 0))
    }

    @Test(arguments: eachSectionHidden)
    func hidingASectionDropsExactlyItsRows(_ shape: Shape) throws {
        let section = try #require(shape.counts.firstIndex(of: 0))
        #expect(shape.index.count == (shape.hasCalculator ? 1 : 0) + 16)
        #expect(shape.index.index(section: section, offset: 0) == nil)
    }

    // MARK: Other screens

    @Test func theUninstallScreenIndexesItsCandidatesAlone() {
        let index = PaletteRowIndex(sectionCounts: [4])
        #expect(index.count == 4)
        #expect(index.row(at: 0) == .element(section: 0, offset: 0))
        #expect(index.row(at: 3) == .element(section: 0, offset: 3), "the summary header takes no index")
        #expect(index.row(at: 4) == nil)
    }

    @Test func aFilterLeavingOneCandidatePullsTheSelectionToIt() {
        #expect(PaletteRowIndex(sectionCounts: [1]).clamped(3) == 0)
    }

    @Test func anArgumentsChoicesAreItsOnlySection() {
        let index = PaletteRowIndex(sectionCounts: [3])
        #expect(index.count == 3)
        #expect(index.row(at: 2) == .element(section: 0, offset: 2))
    }

    @Test func aFreeTextArgumentHasNothingToIndex() {
        let index = PaletteRowIndex(sectionCounts: [0])
        #expect(index.count == 0)
        #expect(index.row(at: 0) == nil)
        #expect(index.clamped(0) == 0)
        #expect(index.clamped(5) == 0)
    }

    @Test func theClipboardIndexesPinnedAndDatedEntriesAlike() {
        let index = PaletteRowIndex(sectionCounts: [2, 5, 3])
        #expect(index.count == 10)
        #expect(index.row(at: 1) == .element(section: 0, offset: 1))
        #expect(index.row(at: 2) == .element(section: 1, offset: 0))
        #expect(index.index(section: 0, offset: 0) == 0, "pinning lifts a row to the head of the list")
    }

    @Test func calculatorHistoryLeadsWithTheLiveCard() {
        let index = Self.historyCard.index
        #expect(index.count == 6)
        #expect(index.row(at: 0) == .calculator)
        #expect(index.row(at: 1) == .element(section: 0, offset: 0))
        #expect(index.row(at: 4) == .element(section: 1, offset: 0))
        #expect(index.index(section: 1, offset: 1) == 5)
    }

    @Test func clearingTheFieldDropsTheCardFromHistory() {
        let index = PaletteRowIndex(sectionCounts: [3, 2])
        #expect(index.count == 5)
        #expect(index.row(at: 0) == .element(section: 0, offset: 0))
    }

    @Test func theEmojiGridIndexesEveryCell() {
        let index = PaletteRowIndex(sectionCounts: [8, 20, 5])
        #expect(index.count == 33)
        #expect(index.row(at: 8) == .element(section: 1, offset: 0))
    }

    // MARK: Every shape

    @Test(arguments: namedShapes + eachSectionAlone + eachSectionHidden + smallShapes)
    func everyIndexInvertsToItself(_ shape: Shape) throws {
        let index = shape.index
        for flat in 0..<index.count {
            switch try #require(index.row(at: flat), "index \(flat) resolves to a row") {
            case .calculator:
                #expect(flat == 0, "the card only ever sits at index 0")
            case .element(let section, let offset):
                #expect(index.index(section: section, offset: offset) == flat)
            }
        }
    }

    @Test(arguments: smallShapes)
    func theRowCountIsTheCardPlusEverySection(_ shape: Shape) {
        #expect(shape.index.count == (shape.hasCalculator ? 1 : 0) + shape.counts.reduce(0, +))
    }

    @Test(arguments: smallShapes)
    func noTwoIndicesResolveToTheSameRow(_ shape: Shape) {
        let index = shape.index
        let rows = (0..<index.count).compactMap(index.row(at:)).map(String.init(describing:))
        #expect(Set(rows).count == rows.count)
    }

    @Test(arguments: [single, withCalculator, sections, launcher, gapped])
    func aSelectionClampsAtBothEnds(_ shape: Shape) {
        let index = shape.index
        #expect(index.clamped(-1) == 0)
        #expect(index.clamped(-99) == 0)
        #expect(index.clamped(index.count) == index.count - 1)
        #expect(index.clamped(index.count + 50) == index.count - 1)
        #expect(index.row(at: index.clamped(Int.max)) != nil)
        #expect(index.row(at: index.clamped(Int.min)) != nil)
    }
}
