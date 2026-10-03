/// Orders two installs of one app by `CFBundleShortVersionString`.
///
/// Several versions of one bundle id at once is ordinary — xcodes, JetBrains Toolbox, a
/// beta kept beside a release — so the launcher has to pick, and picking by directory
/// enumeration order picked whichever the filesystem yielded first. The version is taken
/// as a string rather than a `Bundle`, so this stays in the pure layer and can be
/// exercised by a harness.
///
/// This orders versions, and nothing else. It makes no claim that a stable release
/// outranks a higher-numbered beta: `26.0` and `27.0-beta.1` order as their numbers say,
/// and which one a launcher should open is a product decision, not a version rule.
struct AppBundleVersion: Comparable, Sendable {
    /// Numbers, then whether this is a release, then the prerelease ordinal.
    ///
    /// The release flag comes before the ordinal on purpose: an ordinal only orders
    /// prereleases of the *same* numbers, so `27.0` has to beat `27.0-beta.3` before
    /// beta.4 is compared with beta.3.
    private let rank: [Int]

    /// Nil for anything unreadable, so a bundle with no version never outranks one that
    /// has a real one and the caller keeps the entry it already built.
    init?(_ text: String) {
        let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let halves = body.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)

        var numbers: [Int] = []
        for part in halves[0].split(separator: ".", omittingEmptySubsequences: false) {
            guard let number = Self.number(part) else { return nil }
            numbers.append(number)
        }
        guard !numbers.isEmpty else { return nil }

        // No `-` at all is a release. Anything after one is a prerelease, and only a
        // numeric suffix orders among prereleases of the same numbers; an unknown channel
        // ranks below every numbered one rather than being guessed at.
        let isRelease = halves.count == 1
        var ordinal = 0
        if halves.count == 2 {
            ordinal = Self.ordinal(halves[1]) ?? 0
        }

        rank = numbers + [isRelease ? 1 : 0, ordinal]
    }

    /// Compares component by component. A missing component reads as 0, so `26.6` outranks
    /// `9.4` — comparing lengths first would have let the shorter, older string win, and
    /// `27.0` would have lost to its own `27.0-beta.3` because that one carries an extra
    /// ordinal. Padding to the longer rank keeps the prerelease flag in the same column.
    static func < (lhs: Self, rhs: Self) -> Bool {
        let width = max(lhs.rank.count, rhs.rank.count)
        for column in 0..<width {
            let left = column < lhs.rank.count ? lhs.rank[column] : 0
            let right = column < rhs.rank.count ? rhs.rank[column] : 0
            if left != right { return left < right }
        }
        return false
    }

    /// The count in a `-beta.3` suffix. Any other channel reads as unreadable and is
    /// reported as nil, which ranks it below every numbered prerelease.
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