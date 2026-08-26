import Foundation

/// Orchestrates multi-engine web searches with parallel tasks, timeouts, caching, and consensus scoring.
public final class WebSearchAggregator: Sendable {
    private let cache: WebSearchCacheStore
    private let session: URLSession

    public init(cache: WebSearchCacheStore = WebSearchCacheStore(), session: URLSession = .shared) {
        self.cache = cache
        self.session = session
    }

    public func search(
        query: String,
        engines: Set<WebSearchEngineType> = [.yahoo, .duckDuckGo, .news, .wikipedia],
        timeoutSeconds: Double = 4.0
    ) async -> [WebSearchResult] {
        let parsed = WebSearchQuery(query: query)
        let cacheKey = "\(parsed.category.rawValue):\(parsed.searchTerm)"

        if let cached = await cache.get(key: cacheKey) {
            return cached
        }

        let session = self.session
        var selectedEngines = engines
        if parsed.category == .wikipedia {
            selectedEngines = [.wikipedia]
        } else if parsed.category == .news {
            selectedEngines = [.news, .yahoo, .duckDuckGo]
        }

        let engineResults: [[WebSearchResult]] = await withTaskGroup(of: [WebSearchResult]?.self) { group in
            for engine in selectedEngines {
                group.addTask {
                    do {
                        return try await withThrowingTaskGroup(of: [WebSearchResult].self) { innerGroup in
                            innerGroup.addTask {
                                switch engine {
                                case .duckDuckGo:
                                    return try await DuckDuckGoScraper.search(query: parsed.searchTerm, session: session)
                                case .brave:
                                    return try await BraveSearchScraper.search(query: parsed.searchTerm, session: session)
                                case .aol:
                                    return try await AolSearchScraper.search(query: parsed.searchTerm, session: session)
                                case .yahoo:
                                    return try await YahooSearchScraper.search(query: parsed.searchTerm, session: session)
                                case .wikipedia:
                                    return try await WikipediaEngine.search(query: parsed.searchTerm, session: session)
                                case .news:
                                    return try await NewsRSSEngine.search(query: parsed.searchTerm, session: session)
                                }
                            }
                            innerGroup.addTask {
                                try await Task.sleep(nanoseconds: UInt64(timeoutSeconds * 1_000_000_000))
                                return []
                            }
                            return try await innerGroup.next() ?? []
                        }
                    } catch {
                        return []
                    }
                }
            }

            var aggregated: [[WebSearchResult]] = []
            for await res in group {
                if let res, !res.isEmpty {
                    aggregated.append(res)
                }
            }
            return aggregated
        }

        let scored = ConsensusScorer.score(engineResults: engineResults)
        await cache.set(key: cacheKey, results: scored)
        return scored
    }
}
