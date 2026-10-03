/// Orders two installs of one app by `CFBundleShortVersionString`.
///
/// Orders versions and nothing else: `26.0` and `27.0-beta.1` order as their numbers say,
/// and which one a launcher should open is the caller's decision.
struct AppBundleVersion: Comparable, Sendable {
    /// A release outranks any prerelease of the same numbers, so `27.0` beats `27.0-beta.3`.
    private let isRelease: Bool
    /// The count in a `-beta.3` suffix; 0 for a release, or for a channel with no count.
    private let ordinal: Int
    /// Kept apart from the two above so padding a short version cannot shift the release flag
    /// into a numeric column, which made `26.0-beta.2` outrank its own `26.0.0`.
    private let numbers: [Int]

    /// Nil for anything unreadable, so a bundle with no version never outranks one that has
    /// a real one and the caller keeps the entry it already built.
    init?(_ text: String) {
        let halves = text.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)

        var numbers: [Int] = []
        for part in halves[0].split(separator: ".", omittingEmptySubsequences: false) {
            guard let number = Self.number(part) else { return nil }
            numbers.append(number)
        }
        guard !numbers.isEmpty else { return nil }

        self.numbers = numbers
        self.isRelease = halves.count == 1
        self.ordinal = halves.count == 2 ? Self.ordinal(halves[1]) ?? 0 : 0
    }

    /// Compares component by component, then release before prerelease, then the ordinal.
    /// A missing component reads as 0, so `26.6` outranks `9.4` where text order has it backwards.
    static func < (lhs: Self, rhs: Self) -> Bool {
        guard let order = lhs.compare(to: rhs) else { return false }
        return order.isLess
    }

    /// Pads the numbers the way `<` does, so `27.0` and `27.0.0` are one version rather than
    /// merely comparable. Synthesised `==` would compare the arrays and call them different.
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.compare(to: rhs)?.isEqual == true
    }

    private func compare(to other: Self) -> (isEqual: Bool, isLess: Bool)? {
        let width = max(numbers.count, other.numbers.count)
        for column in 0..<width {
            let mine = column < numbers.count ? numbers[column] : 0
            let theirs = column < other.numbers.count ? other.numbers[column] : 0
            if mine != theirs { return (false, mine < theirs) }
        }
        if isRelease != other.isRelease { return (false, !isRelease) }
        if ordinal != other.ordinal { return (false, ordinal < other.ordinal) }
        return (true, false)
    }

    /// Any channel but `beta.N` reads as uncounted, ranking it below every numbered beta.
    private static func ordinal(_ suffix: Substring) -> Int? {
        let parts = suffix.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 2, parts[0] == "beta" else { return nil }
        return number(parts[1])
    }

    /// Rejects a signed or padded field, which `Int` would silently reinterpret.
    private static func number(_ text: Substring) -> Int? {
        guard !text.isEmpty, text.allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
        return Int(text)
    }
}