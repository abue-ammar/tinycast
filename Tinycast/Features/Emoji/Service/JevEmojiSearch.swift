import Foundation
import Observation

/// Optional semantic emoji search. No key means the picker stays on the local index.
@MainActor
@Observable
final class JevEmojiSearch {
    private static let account = UUID(uuidString: "C4E8A1D2-6B37-4F09-8C55-1A9D0E7B2F64")!
    private static let debounce: Duration = .milliseconds(280)
    private static let cacheLimit = 32

    private(set) var glyphs: [String] = []
    private(set) var isAsking = false
    private(set) var hasKey = false

    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var cache: [String: [String]] = [:]
    @ObservationIgnored private var cacheOrder: [String] = []

    init() {
        hasKey = (try? Self.store.secret(for: Self.account))?.isEmpty == false
    }

    func storedKey() -> String? {
        guard let key = try? Self.store.secret(for: Self.account), !key.isEmpty else { return nil }
        return key
    }

    func saveKey(_ key: String) {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            try? Self.store.removeSecret(for: Self.account)
            hasKey = false
        } else {
            try? Self.store.setSecret(trimmed, for: Self.account)
            hasKey = true
        }
        cache.removeAll()
        cacheOrder.removeAll()
    }

    /// Debounced. A short query, or no key, clears any Jev hits already on screen.
    func note(_ raw: String, index: EmojiIndex) {
        task?.cancel()
        let query = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard hasKey, query.count >= JevEmojiRanking.minimumQueryLength else {
            glyphs = []
            isAsking = false
            return
        }
        let folded = query.lowercased()
        if let hit = cache[folded] {
            glyphs = hit
            isAsking = false
            return
        }
        isAsking = true
        glyphs = []
        let entries = index.entries
        task = Task { [weak self] in
            try? await Task.sleep(for: Self.debounce)
            guard !Task.isCancelled, let self else { return }
            guard let key = self.storedKey() else {
                self.isAsking = false
                return
            }
            let ranked = await JevEmojiClient.search(query: query, entries: entries, apiKey: key)
            guard !Task.isCancelled else { return }
            self.remember(folded, ranked)
            self.glyphs = ranked
            self.isAsking = false
        }
    }

    private func remember(_ query: String, _ glyphs: [String]) {
        if cache[query] == nil { cacheOrder.append(query) }
        cache[query] = glyphs
        while cacheOrder.count > Self.cacheLimit {
            cache.removeValue(forKey: cacheOrder.removeFirst())
        }
    }

    private static let store = KeychainSecretStore(scope: "jev-emoji")
}

/// Cacheless, never `URLSession.shared`. A bad key or a timeout leaves the local results alone.
enum JevEmojiClient {
    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil
        return URLSession(configuration: config)
    }()

    nonisolated static func search(
        query: String, entries: [EmojiEntry], apiKey: String
    ) async -> [String] {
        guard let body = JevEmojiRanking.requestBody(query: query, entries: entries) else {
            return []
        }
        let data = await post(body, apiKey: apiKey)
        guard let data else { return [] }
        return JevEmojiRanking.glyphs(in: data, catalog: entries)
    }

    private nonisolated static func post(_ body: Data, apiKey: String) async -> Data? {
        let first = await send(body, apiKey: apiKey)
        if first.status == 429 || first.status == 529 {
            try? await Task.sleep(for: .milliseconds(400))
            let second = await send(body, apiKey: apiKey)
            return second.status == 200 ? second.data : nil
        }
        return first.status == 200 ? first.data : nil
    }

    private nonisolated static func send(
        _ body: Data, apiKey: String
    ) async -> (status: Int, data: Data?) {
        var request = URLRequest(url: JevEmojiRanking.endpoint, timeoutInterval: 12)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = body
        guard let (data, response) = try? await session.data(for: request) else {
            return (0, nil)
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        return (status, data)
    }
}
