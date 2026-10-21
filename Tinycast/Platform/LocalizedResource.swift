import Foundation

/// Resolving a `LocalizedStringResource` through `String(localized:)` re-reads the string table on
/// every call. The resource pins the locale it was built with — a region-qualified tag such as
/// `zh_CN`, which names no `.lproj` — and the lookup that follows reloads the table instead of
/// reusing it, so the cost tracks the table's size: ~1.7 ms per call in `zh-Hans` against 0.3 µs
/// for the same key through `String.LocalizationValue` (issue #1667).
///
/// `resolved()` keeps the resource at the call site — the compiler still extracts its key — and
/// takes the cached path to the same table. It returns what `String(localized:)` would: a value
/// equal to the key means the table had no entry, so the resource's own default stands in. That
/// second lookup only happens on a miss.
extension LocalizedStringResource {
    func resolved() -> String {
        let value = String(localized: String.LocalizationValue(key))
        return value == key ? String(localized: defaultValue) : value
    }
}
