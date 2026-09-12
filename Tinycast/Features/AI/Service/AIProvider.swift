import Foundation

typealias AIProviderStream = AsyncThrowingStream<AIStreamEvent, Error>

/// Never main-bound: a stream does its own IO and decoding, and hands the main actor only events.
protocol AIProvider: Sendable {
    func stream(_ request: AIRequest) -> AIProviderStream
}
