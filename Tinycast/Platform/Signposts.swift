import os

/// Coarse permanent intervals; free at runtime unless an Instruments session is attached.
enum Signposts {
    private static let signposter = OSSignposter(
        subsystem: "com.tinycast.perf", category: "Performance")

    /// Own the `defer`: `withIntervalSignpost` skips its end event when the wrapped work throws.
    static func interval<T>(_ name: StaticString, around work: () throws -> T) rethrows -> T {
        let state = signposter.beginInterval(name)
        defer { signposter.endInterval(name, state) }
        return try work()
    }

    static func interval<T>(
        _ name: StaticString, around work: () async throws -> T
    ) async rethrows
        -> T
    {
        let state = signposter.beginInterval(name)
        defer { signposter.endInterval(name, state) }
        return try await work()
    }
}
