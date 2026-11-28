import Testing

@testable import Tinycast

struct FavoritesTests {
    @Test func allTenSlotsHaveDistinctDigits() {
        #expect(FavoriteSlots.digits.count == 10)
        #expect(Set(FavoriteSlots.digits).count == FavoriteSlots.digits.count)
    }

    @Test(arguments: [("1", 0), ("9", 8), ("0", 9), ("a", nil)] as [(Character, Int?)])
    func digitSelectsItsSlot(_ digit: Character, _ index: Int?) {
        #expect(FavoriteSlots.index(for: digit) == index)
    }

    @Test(
        arguments: Array(
            zip(
                [18, 19, 20, 21, 23, 22, 26, 28, 25, 29] as [UInt16], 0..<10)))
    func physicalKeySelectsItsSlot(_ keyCode: UInt16, _ index: Int) {
        #expect(FavoriteSlots.index(forKeyCode: keyCode) == index)
    }

    @Test func unknownKeyHasNoSlot() {
        #expect(FavoriteSlots.index(forKeyCode: 0) == nil)
    }

    @Test(arguments: [(0, "1"), (9, "0"), (10, nil), (-1, nil)] as [(Int, Character?)])
    func slotDisplaysItsDigit(_ index: Int, _ digit: Character?) {
        #expect(FavoriteSlots.digit(at: index) == digit)
    }

    @Test(arguments: FavoriteSlots.digits.indices)
    func displayedDigitSelectsTheSameSlot(_ index: Int) throws {
        let digit = try #require(FavoriteSlots.digit(at: index))
        #expect(FavoriteSlots.index(for: digit) == index)
    }
}
