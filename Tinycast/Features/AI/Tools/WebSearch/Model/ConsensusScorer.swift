import Foundation

public enum ConsensusScorer {
    /// SearXNG-inspired Reciprocal Rank Fusion (RRF) with engine agreement bonus.
    /// Score(u) = (Agreeing Engines Count) * sum_e ( weight(e) / (rank_e + 60) )
    public static func score(
        engineResults: [[WebSearchResult]],
        weights: [WebSearchEngineType: Double] = [:]
    ) -> [WebSearchResult] {
        struct ScoredEntry {
            var primaryResult: WebSearchResult
            var agreeingEngines: Set<WebSearchEngineType>
            var rawRRFScore: Double
            var bestSnippet: String
        }

        var groups: [String: ScoredEntry] = [:]

        for results in engineResults {
            for result in results {
                let key = URLNormalizer.deduplicationKey(for: result.url)
                let engine = result.engine
                let weight = weights[engine] ?? engine.defaultWeight
                let rrf = weight / Double(result.rank + 60)

                if var existing = groups[key] {
                    existing.agreeingEngines.insert(engine)
                    existing.rawRRFScore += rrf
                    if result.snippet.count > existing.bestSnippet.count {
                        existing.bestSnippet = result.snippet
                    }
                    groups[key] = existing
                } else {
                    groups[key] = ScoredEntry(
                        primaryResult: result,
                        agreeingEngines: [engine],
                        rawRRFScore: rrf,
                        bestSnippet: result.snippet
                    )
                }
            }
        }

        var finalResults: [WebSearchResult] = []
        for entry in groups.values {
            let engineCount = Double(entry.agreeingEngines.count)
            let totalScore = engineCount * entry.rawRRFScore
            let cleanURL = URLNormalizer.normalize(entry.primaryResult.url)
            let scored = WebSearchResult(
                id: entry.primaryResult.id,
                title: entry.primaryResult.title,
                url: cleanURL,
                snippet: entry.bestSnippet,
                engine: entry.primaryResult.engine,
                rank: entry.primaryResult.rank,
                score: totalScore,
                publishedDate: entry.primaryResult.publishedDate
            )
            finalResults.append(scored)
        }

        return finalResults.sorted { $0.score > $1.score }
    }
}
