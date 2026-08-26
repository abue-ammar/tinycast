import Foundation

/// Central registry managing all available tools and their execution.
public final class AIToolRegistry: Sendable {
    public static let shared = AIToolRegistry()

    private let searchAggregator: WebSearchAggregator
    private let pageReader: WebPageReader
    private let locationProvider: LocationProvider
    private let weatherService: WeatherService
    private let calculatorRunner: CalculatorToolRunner

    public init(
        searchAggregator: WebSearchAggregator = WebSearchAggregator(),
        pageReader: WebPageReader = WebPageReader(),
        locationProvider: LocationProvider = LocationProvider(),
        weatherService: WeatherService? = nil,
        calculatorRunner: CalculatorToolRunner = CalculatorToolRunner()
    ) {
        self.searchAggregator = searchAggregator
        self.pageReader = pageReader
        self.locationProvider = locationProvider
        self.weatherService = weatherService ?? WeatherService(locationProvider: locationProvider)
        self.calculatorRunner = calculatorRunner
    }

    /// All tool definitions available for the model to use
    public var availableTools: [AIToolDefinition] {
        [
            .webSearch,
            .webFetch,
            .calculate,
            .getLocation,
            .getWeather
        ]
    }

    /// Executes a tool call asynchronously and returns the formatted result
    public func execute(call: AIToolCall) async -> AIToolResult {
        switch call.name {
        case "web_search":
            return await executeWebSearch(call: call)
        case "web_fetch":
            return await executeWebFetch(call: call)
        case "calculate":
            return executeCalculate(call: call)
        case "get_location":
            return await executeGetLocation(call: call)
        case "get_weather":
            return await executeGetWeather(call: call)
        default:
            return AIToolResult(
                callID: call.id,
                name: call.name,
                output: "Unknown tool: \(call.name)"
            )
        }
    }

    private func executeWebSearch(call: AIToolCall) async -> AIToolResult {
        var query = ""
        if let data = call.argumentsJSON.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let q = json["query"] as? String {
            query = q
        } else {
            query = call.argumentsJSON
        }

        let results = await searchAggregator.search(query: query)
        let formatted = results.prefix(5).map { res in
            "[\(res.title)](\(res.url))\n\(res.snippet)"
        }.joined(separator: "\n\n")

        return AIToolResult(
            callID: call.id,
            name: call.name,
            output: formatted.isEmpty ? "No search results found for '\(query)'." : formatted
        )
    }

    private func executeWebFetch(call: AIToolCall) async -> AIToolResult {
        var urlString = ""
        var maxChars = 4000
        if let data = call.argumentsJSON.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let u = json["url"] as? String { urlString = u }
            if let m = json["max_characters"] as? Int { maxChars = m }
        }

        guard let url = URL(string: urlString) else {
            return AIToolResult(
                callID: call.id,
                name: call.name,
                output: "Invalid URL: \(urlString)"
            )
        }

        do {
            let markdown = try await pageReader.read(url: url, maxCharacters: maxChars)
            return AIToolResult(
                callID: call.id,
                name: call.name,
                output: markdown
            )
        } catch {
            return AIToolResult(
                callID: call.id,
                name: call.name,
                output: "Failed to fetch page: \(error.localizedDescription)"
            )
        }
    }

    private func executeCalculate(call: AIToolCall) -> AIToolResult {
        var expr = ""
        if let data = call.argumentsJSON.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let e = json["expression"] as? String {
            expr = e
        } else {
            expr = call.argumentsJSON
        }

        let output = calculatorRunner.calculate(expression: expr)
        return AIToolResult(
            callID: call.id,
            name: call.name,
            output: output
        )
    }

    private func executeGetLocation(call: AIToolCall) async -> AIToolResult {
        if let loc = await locationProvider.getLocation() {
            return AIToolResult(
                callID: call.id,
                name: call.name,
                output: loc.summary
            )
        } else {
            return AIToolResult(
                callID: call.id,
                name: call.name,
                output: "Could not determine location automatically."
            )
        }
    }

    private func executeGetWeather(call: AIToolCall) async -> AIToolResult {
        var location: String?
        var days = 1
        if let data = call.argumentsJSON.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let loc = json["location"] as? String { location = loc }
            if let d = json["days"] as? Int { days = d }
        }

        let output = await weatherService.getWeather(location: location, days: days)
        return AIToolResult(
            callID: call.id,
            name: call.name,
            output: output
        )
    }
}
