import Foundation

/// Thread-safe in-memory LRU cache for search results with TTL expiration.
public actor WebSearchCacheStore {
    private struct Entry {
        let results: [WebSearchResult]
        let timestamp: ContinuousClock.Instant
    }

    private var cache: [String: Entry] = [:]
    private let ttl: Duration
    private let capacity: Int

    public init(ttl: Duration = .seconds(900), capacity: Int = 50) {
        self.ttl = ttl
        self.capacity = capacity
    }

    public func get(key: String) -> [WebSearchResult]? {
        guard let entry = cache[key] else { return nil }
        let now = ContinuousClock().now
        if now - entry.timestamp > ttl {
            cache.removeValue(forKey: key)
            return nil
        }
        return entry.results
    }

    public func set(key: String, results: [WebSearchResult]) {
        if cache.count >= capacity {
            // Drop earliest entry
            if let oldestKey = cache.min(by: { $0.value.timestamp < $1.value.timestamp })?.key {
                cache.removeValue(forKey: oldestKey)
            }
        }
        cache[key] = Entry(results: results, timestamp: ContinuousClock().now)
    }

    public func clear() {
        cache.removeAll()
    }
}
