# App launcher & fuzzy match

`AppIndex.scan()` runs off-main, enumerates the standard `/Applications` dirs, and dedups by bundle ID
(first dir wins).

`FuzzyMatch.score` is a tiered scorer: exact → prefix → substring / word-start → subsequence with
consecutive / word-boundary bonuses. Rankings are memoized one query deep.

> **Invariant:** `Tools/fuzz-test.swift` contains a **copy** of `FuzzyMatch` from
> `Smallcast/Core/AppIndex.swift`. If you change the scoring in one, mirror it in the other or the test
> is meaningless.

Icons go through a count-capped `NSCache` (`IconCache`).
