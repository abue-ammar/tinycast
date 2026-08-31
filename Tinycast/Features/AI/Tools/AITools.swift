// Native AI Tool Calling Subsystem for Tinycast
// Consolidated tools, registry, web search aggregator, and web fetch parser.

import CoreLocation
import Foundation
import PDFKit


// MARK: - AITool.swift
/// Defines tools that the AI model can execute during a conversation.
public struct AIToolDefinition: Codable, Equatable, Sendable {
    public let name: String
    public let description: String
    public let parametersJSON: String

    public init(name: String, description: String, parametersJSON: String) {
        self.name = name
        self.description = description
        self.parametersJSON = parametersJSON
    }

    /// Built-in web_search tool definition
    public static let webSearch = AIToolDefinition(
        name: "web_search",
        description: "Performs live web searches using multi-engine search aggregators (DuckDuckGo, Brave, Yahoo, AOL, Wikipedia). Perform 1 to 2 targeted searches only, then immediately synthesize the final answer for the user. Do not call this repeatedly in a loop.",
        parametersJSON: """
        {
          "type": "object",
          "properties": {
            "query": {
              \"type\": \"string\",
              \"description\": \"The search query (e.g. 'iOS 26 features', 'Tamil Nadu news today'). Keep keywords concise and search for current info without hardcoding past years.\"
            },
            \"category\": {
              \"type\": \"string\",
              \"enum\": [\"general\", \"news\", \"wikipedia\"],
              \"description\": \"Optional search category (default: 'general', use 'news' for current events)\"
            }
          },
          \"required\": [\"query\"]
        }
        """
    )

    /// Built-in web_fetch tool definition
    public static let webFetch = AIToolDefinition(
        name: "web_fetch",
        description: "Fetches and extracts clean Markdown text from a specific webpage URL or PDF document URL. Use this ONLY when the user explicitly provides a URL in their prompt (e.g. 'summarize https://example.com' or 'read this link'). NEVER call this automatically after web_search.",
        parametersJSON: """
        {
          "type": "object",
          "properties": {
            "url": {
              \"type\": \"string\",
              \"description\": \"The HTTP or HTTPS URL to fetch and read\"
            },
            \"max_characters\": {
              \"type\": \"integer\",
              \"description\": \"Maximum characters to extract (default: 4000)\"
            }
          },
          \"required\": [\"url\"]
        }
        """
    )

    /// Built-in calculate tool definition
    public static let calculate = AIToolDefinition(
        name: "calculate",
        description: "Fast on-device calculator for exact arithmetic, scientific math (sqrt, log, sin, cos, pow, factorial), percentage calculations, unit conversions across 11 categories (length, weight, temperature, area, volume, speed, digital storage, data transfer rate, pressure, angle), currency conversions (USD, EUR, GBP, INR, JPY, CAD, AUD, BTC, ETH, etc.), and date/time calculations (e.g. 'days until Dec 25', 'today + 45 days', 'hours until 6pm').",
        parametersJSON: """
        {
          "type": "object",
          "properties": {
            "expression": {
              \"type\": \"string\",
              \"description\": \"The math expression, unit conversion, currency exchange, or date calculation to evaluate (e.g. '(45 * 12) / 3', '50 kg in lbs', '15% off 250', '$120 in EUR', 'days until Christmas')\"
            }
          },
          \"required\": [\"expression\"]
        }
        """
    )

    /// Built-in get_location tool definition
    public static let getLocation = AIToolDefinition(
        name: "get_location",
        description: "Retrieves the user's current physical location (device GPS / CoreLocation) including exact neighborhood/sublocality, city, region, postal code, precise coordinates, and timezone.",
        parametersJSON: """
        {
          "type": "object",
          "properties": {}
        }
        """
    )

    /// Built-in get_weather tool definition
    public static let getWeather = AIToolDefinition(
        name: "get_weather",
        description: "Gets current weather conditions (temperature, feels-like, condition description, humidity, wind speed) and optional multi-day forecast for a given city or the user's current location.",
        parametersJSON: """
        {
          "type": "object",
          "properties": {
            "location": {
              \"type\": \"string\",
              \"description\": \"City and state/country or 'current' for user's current location (e.g. 'Tokyo, Japan', 'San Francisco', 'London', 'current')\"
            },
            \"days\": {
              \"type\": \"integer\",
              \"description\": \"Number of forecast days (1 for current only, up to 7 for multi-day forecast)\"
            }
          }
        }
        """
    )
}

/// Represents a tool invocation request made by an AI model during streaming.
public struct AIToolCall: Codable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let argumentsJSON: String

    public init(id: String, name: String, argumentsJSON: String) {
        self.id = id
        self.name = name
        self.argumentsJSON = argumentsJSON
    }
}

/// Represents the output of a completed tool execution.
public struct AIToolResult: Codable, Equatable, Sendable {
    public let callID: String
    public let name: String
    public let output: String

    public init(callID: String, name: String, output: String) {
        self.callID = callID
        self.name = name
        self.output = output
    }
}

// MARK: - AIToolRegistry.swift
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

// MARK: - CalculatorToolRunner.swift
/// Fast on-device mathematical expression evaluator using NSExpression.
public final class CalculatorToolRunner: Sendable {
    public init() {}

    public func calculate(expression: String) -> String {
        let trimmed = expression.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return "Error: Expression cannot be empty."
        }

        let exprString = trimmed
            .replacingOccurrences(of: "×", with: "*")
            .replacingOccurrences(of: "÷", with: "/")
            .replacingOccurrences(of: "^", with: "**")

        let mathExpr = NSExpression(format: exprString)
        if let mathVal = mathExpr.expressionValue(with: nil, context: nil) as? NSNumber {
            let formatter = NumberFormatter()
            formatter.maximumFractionDigits = 8
            formatter.minimumFractionDigits = 0
            formatter.numberStyle = .decimal
            if let formatted = formatter.string(from: mathVal) {
                return "Result: \(formatted)"
            }
            return "Result: \(mathVal)"
        }

        return "Calculation Error: Unable to evaluate expression."
    }
}

// MARK: - LocationProvider.swift
public struct UserLocationInfo: Equatable, Sendable {
    public let subLocality: String
    public let city: String
    public let region: String
    public let country: String
    public let countryCode: String
    public let postalCode: String
    public let latitude: Double
    public let longitude: Double
    public let timezone: String
    public let source: String

    public init(
        subLocality: String = "",
        city: String,
        region: String,
        country: String,
        countryCode: String,
        postalCode: String = "",
        latitude: Double,
        longitude: Double,
        timezone: String,
        source: String = "Device GPS (CoreLocation)"
    ) {
        self.subLocality = subLocality
        self.city = city
        self.region = region
        self.country = country
        self.countryCode = countryCode
        self.postalCode = postalCode
        self.latitude = latitude
        self.longitude = longitude
        self.timezone = timezone
        self.source = source
    }

    public var summary: String {
        var parts: [String] = []
        if !subLocality.isEmpty { parts.append(subLocality) }
        if !city.isEmpty && city != subLocality { parts.append(city) }
        if !region.isEmpty, region != city { parts.append(region) }
        if !country.isEmpty { parts.append(country) }
        if !postalCode.isEmpty { parts.append(postalCode) }
        let place = parts.joined(separator: ", ")

        var lines: [String] = [
            "Exact Location: \(place)",
            "Coordinates: \(latitude), \(longitude)",
            "Timezone: \(timezone)",
            "Accuracy Source: \(source)"
        ]
        if !subLocality.isEmpty {
            lines.insert("Area / Neighborhood: \(subLocality)", at: 1)
        }
        if !city.isEmpty {
            lines.insert("City: \(city)", at: 2)
        }
        return lines.joined(separator: "\n")
    }
}

@MainActor
private final class CoreLocationFetcher: NSObject, @preconcurrency CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<CLLocation?, Never>?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
    }

    func requestLocation() async -> CLLocation? {
        let status = manager.authorizationStatus
        if status == .notDetermined {
            manager.requestAlwaysAuthorization()
        } else if status == .denied || status == .restricted {
            return nil
        }

        return await withCheckedContinuation { cont in
            self.continuation = cont
            self.manager.startUpdatingLocation()

            let timeoutSec = (status == .notDetermined) ? 8 : 4
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(timeoutSec))
                guard let self, let cont = self.continuation else { return }
                self.continuation = nil
                self.manager.stopUpdatingLocation()
                cont.resume(returning: nil)
            }
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        manager.stopUpdatingLocation()
        if let cont = continuation {
            continuation = nil
            cont.resume(returning: location)
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        manager.stopUpdatingLocation()
        if let cont = continuation {
            continuation = nil
            cont.resume(returning: nil)
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        if status == .authorizedAlways || status == .authorized {
            manager.startUpdatingLocation()
        } else if status == .denied || status == .restricted {
            manager.stopUpdatingLocation()
            if let cont = continuation {
                continuation = nil
                cont.resume(returning: nil)
            }
        }
    }
}

public final class LocationProvider: @unchecked Sendable {
    private let session: URLSession

    public init(session: URLSession? = nil) {
        if let session {
            self.session = session
        } else {
            let config = URLSessionConfiguration.default
            config.timeoutIntervalForRequest = 4
            config.timeoutIntervalForResource = 5
            self.session = URLSession(configuration: config)
        }
    }

    public func getLocation() async -> UserLocationInfo? {
        // 1. Try CoreLocation first for exact GPS accuracy
        if let coreLoc = await fetchCoreLocation() {
            return coreLoc
        }

        // 2. Fall back to IP Geolocation if CoreLocation is denied/unavailable
        if let ipLocation = await fetchIPLocation() {
            return ipLocation
        }

        return nil
    }

    private func fetchCoreLocation() async -> UserLocationInfo? {
        let fetcher = await MainActor.run { CoreLocationFetcher() }
        guard let location = await fetcher.requestLocation() else {
            return nil
        }

        let geocoder = CLGeocoder()
        let placemarks = try? await geocoder.reverseGeocodeLocation(location)
        if let place = placemarks?.first {
            let subLocality = place.subLocality ?? place.thoroughfare ?? ""
            let city = place.locality ?? place.subAdministrativeArea ?? place.name ?? ""
            let region = place.administrativeArea ?? ""
            let country = place.country ?? ""
            let countryCode = place.isoCountryCode ?? ""
            let postalCode = place.postalCode ?? ""
            let timezone = place.timeZone?.identifier ?? TimeZone.current.identifier

            return UserLocationInfo(
                subLocality: subLocality,
                city: city,
                region: region,
                country: country,
                countryCode: countryCode,
                postalCode: postalCode,
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude,
                timezone: timezone,
                source: "Device GPS (CoreLocation - High Accuracy)"
            )
        }

        return UserLocationInfo(
            city: "",
            region: "",
            country: "",
            countryCode: "",
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            timezone: TimeZone.current.identifier,
            source: "Device GPS (CoreLocation - High Accuracy)"
        )
    }

    private func fetchIPLocation() async -> UserLocationInfo? {
        guard let url = URL(string: "https://ipwho.is/") else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 4
        request.setValue("Mozilla/5.0 Tinycast/1.0", forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let success = json["success"] as? Bool, success else {
                return nil
            }

            let city = json["city"] as? String ?? ""
            let region = json["region"] as? String ?? ""
            let country = json["country"] as? String ?? ""
            let countryCode = json["country_code"] as? String ?? ""
            let postalCode = json["postal"] as? String ?? ""
            let lat = json["latitude"] as? Double ?? 0.0
            let lon = json["longitude"] as? Double ?? 0.0
            var tz = ""
            if let timezoneObj = json["timezone"] as? [String: Any],
               let tzId = timezoneObj["id"] as? String {
                tz = tzId
            } else {
                tz = TimeZone.current.identifier
            }

            return UserLocationInfo(
                subLocality: "",
                city: city,
                region: region,
                country: country,
                countryCode: countryCode,
                postalCode: postalCode,
                latitude: lat,
                longitude: lon,
                timezone: tz,
                source: "IP Geolocation"
            )
        } catch {
            return nil
        }
    }
}

// MARK: - WeatherService.swift
public final class WeatherService: Sendable {
    private let session: URLSession
    private let locationProvider: LocationProvider

    public init(session: URLSession? = nil, locationProvider: LocationProvider = LocationProvider()) {
        self.locationProvider = locationProvider
        if let session {
            self.session = session
        } else {
            let config = URLSessionConfiguration.default
            config.timeoutIntervalForRequest = 6
            config.timeoutIntervalForResource = 8
            self.session = URLSession(configuration: config)
        }
    }

    public func getWeather(location: String?, days: Int = 1) async -> String {
        let isFahrenheit: Bool = {
            if #available(macOS 13.0, *) {
                return Locale.current.measurementSystem == .us
            } else {
                return Locale.current.usesMetricSystem == false
            }
        }()
        let tempUnit = isFahrenheit ? "fahrenheit" : "celsius"
        let unitSymbol = isFahrenheit ? "°F" : "°C"
        let speedUnit = isFahrenheit ? "mph" : "kmh"

        var targetLat: Double = 0.0
        var targetLon: Double = 0.0
        var resolvedPlace = ""

        let locTrimmed = location?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if locTrimmed.isEmpty || locTrimmed.lowercased() == "current" || locTrimmed.lowercased() == "here" {
            if let userLoc = await locationProvider.getLocation() {
                targetLat = userLoc.latitude
                targetLon = userLoc.longitude
                resolvedPlace = [userLoc.city, userLoc.country].filter { !$0.isEmpty }.joined(separator: ", ")
            } else {
                return "Unable to determine current location. Please specify a city name (e.g. 'weather in Paris')."
            }
        } else {
            // Geocode city name using Open-Meteo Geocoding API
            guard let encoded = locTrimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
                  let geoURL = URL(string: "https://geocoding-api.open-meteo.com/v1/search?name=\(encoded)&count=1&language=en&format=json") else {
                return "Invalid location query: \(locTrimmed)"
            }

            do {
                let (data, response) = try await session.data(from: geoURL)
                guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                    return "Could not geocode location '\(locTrimmed)'."
                }
                guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let results = json["results"] as? [[String: Any]],
                      let first = results.first,
                      let lat = first["latitude"] as? Double,
                      let lon = first["longitude"] as? Double else {
                    return "Location '\(locTrimmed)' not found."
                }
                targetLat = lat
                targetLon = lon
                let name = first["name"] as? String ?? locTrimmed
                let country = first["country"] as? String ?? ""
                let admin1 = first["admin1"] as? String ?? ""
                resolvedPlace = [name, admin1, country].filter { !$0.isEmpty }.joined(separator: ", ")
            } catch {
                return "Failed to search location: \(error.localizedDescription)"
            }
        }

        let forecastDays = min(max(days, 1), 7)
        let weatherURLString = "https://api.open-meteo.com/v1/forecast?latitude=\(targetLat)&longitude=\(targetLon)&current=temperature_2m,relative_humidity_2m,apparent_temperature,precipitation,weather_code,wind_speed_10m&daily=weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max&temperature_unit=\(tempUnit)&wind_speed_unit=\(speedUnit)&precipitation_unit=mm&timeformat=iso8601&timezone=auto&forecast_days=\(forecastDays)"

        guard let weatherURL = URL(string: weatherURLString) else {
            return "Failed to construct weather request URL."
        }

        do {
            let (data, response) = try await session.data(from: weatherURL)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                return "Weather service returned HTTP error."
            }
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return "Invalid response from weather service."
            }

            var output = "Weather for \(resolvedPlace.isEmpty ? "\(targetLat), \(targetLon)" : resolvedPlace):\n\n"

            if let current = json["current"] as? [String: Any] {
                let temp = current["temperature_2m"] as? Double ?? 0
                let apparent = current["apparent_temperature"] as? Double ?? temp
                let humidity = current["relative_humidity_2m"] as? Int ?? 0
                let wind = current["wind_speed_10m"] as? Double ?? 0
                let code = current["weather_code"] as? Int ?? 0
                let desc = Self.descriptionForWeatherCode(code)

                output += "• Current Conditions: \(desc)\n"
                output += "• Temperature: \(Int(round(temp)))\(unitSymbol) (Feels like \(Int(round(apparent)))\(unitSymbol))\n"
                output += "• Humidity: \(humidity)%\n"
                output += "• Wind Speed: \(Int(round(wind))) \(speedUnit)\n"
            }

            if forecastDays > 1, let daily = json["daily"] as? [String: Any],
               let times = daily["time"] as? [String],
               let maxTemps = daily["temperature_2m_max"] as? [Double],
               let minTemps = daily["temperature_2m_min"] as? [Double],
               let codes = daily["weather_code"] as? [Int] {
                let precipProbs = daily["precipitation_probability_max"] as? [Int] ?? []

                output += "\nForecast:\n"
                for i in 0..<min(times.count, forecastDays) {
                    let day = times[i]
                    let maxT = Int(round(maxTemps[i]))
                    let minT = Int(round(minTemps[i]))
                    let condition = Self.descriptionForWeatherCode(codes[i])
                    let rain = (i < precipProbs.count) ? " · Rain: \(precipProbs[i])%" : ""
                    output += "- \(day): \(condition), High: \(maxT)\(unitSymbol), Low: \(minT)\(unitSymbol)\(rain)\n"
                }
            }

            return output
        } catch {
            return "Failed to fetch weather: \(error.localizedDescription)"
        }
    }

    public static func descriptionForWeatherCode(_ code: Int) -> String {
        switch code {
        case 0: return "Clear sky"
        case 1: return "Mainly clear"
        case 2: return "Partly cloudy"
        case 3: return "Overcast"
        case 45, 48: return "Foggy"
        case 51, 53, 55: return "Drizzle"
        case 56, 57: return "Freezing drizzle"
        case 61: return "Slight rain"
        case 63: return "Moderate rain"
        case 65: return "Heavy rain"
        case 66, 67: return "Freezing rain"
        case 71: return "Slight snow"
        case 73: return "Moderate snow"
        case 75: return "Heavy snow"
        case 77: return "Snow grains"
        case 80, 81, 82: return "Rain showers"
        case 85, 86: return "Snow showers"
        case 95: return "Thunderstorm"
        case 96, 99: return "Thunderstorm with hail"
        default: return "Partly cloudy"
        }
    }
}

// MARK: - HTMLToMarkdownConverter.swift
public enum HTMLToMarkdownConverter {
    /// Converts raw HTML string into clean, token-efficient Markdown.
    public static func convert(html: String, maxCharacters: Int = 4000) -> String {
        var text = html

        // 1. Remove scripts, styles, noscript, svg, nav, footer, header, aside, iframe, form
        let removePatterns = [
            #"<script\b[^<]*(?:(?!<\/script>)<[^<]*)*<\/script>"#,
            #"<style\b[^<]*(?:(?!<\/style>)<[^<]*)*<\/style>"#,
            #"<noscript\b[^<]*(?:(?!<\/noscript>)<[^<]*)*<\/noscript>"#,
            #"<svg\b[^<]*(?:(?!<\/svg>)<[^<]*)*<\/svg>"#,
            #"<nav\b[^<]*(?:(?!<\/nav>)<[^<]*)*<\/nav>"#,
            #"<footer\b[^<]*(?:(?!<\/footer>)<[^<]*)*<\/footer>"#,
            #"<header\b[^<]*(?:(?!<\/header>)<[^<]*)*<\/header>"#,
            #"<aside\b[^<]*(?:(?!<\/aside>)<[^<]*)*<\/aside>"#,
            #"<iframe\b[^<]*(?:(?!<\/iframe>)<[^<]*)*<\/iframe>"#,
            #"<form\b[^<]*(?:(?!<\/form>)<[^<]*)*<\/form>"#,
            #"<a\s+[^>]*href=["']javascript:[^"']*["'][^>]*>.*?<\/a>"#
        ]

        for pattern in removePatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) {
                text = regex.stringByReplacingMatches(in: text, options: [], range: NSRange(text.startIndex..., in: text), withTemplate: "")
            }
        }

        // 2. Extract article or main if present
        if let articleRegex = try? NSRegularExpression(pattern: #"<article\b[^>]*>(.*?)<\/article>"#, options: [.caseInsensitive, .dotMatchesLineSeparators]),
           let match = articleRegex.firstMatch(in: text, options: [], range: NSRange(text.startIndex..., in: text)),
           let range = Range(match.range(at: 1), in: text) {
            text = String(text[range])
        } else if let mainRegex = try? NSRegularExpression(pattern: #"<main\b[^>]*>(.*?)<\/main>"#, options: [.caseInsensitive, .dotMatchesLineSeparators]),
                  let match = mainRegex.firstMatch(in: text, options: [], range: NSRange(text.startIndex..., in: text)),
                  let range = Range(match.range(at: 1), in: text) {
            text = String(text[range])
        }

        // 3. Convert headers
        for level in 1...6 {
            let hPattern = "<h\(level)[^>]*>(.*?)</h\(level)>"
            let prefix = String(repeating: "#", count: level) + " "
            if let regex = try? NSRegularExpression(pattern: hPattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) {
                text = regex.stringByReplacingMatches(in: text, options: [], range: NSRange(text.startIndex..., in: text), withTemplate: "\n\n\(prefix)$1\n\n")
            }
        }

        // 4. Convert links: <a href="url">text</a> -> [text](url)
        let linkPattern = #"<a\s+[^>]*href=["']([^"']+)["'][^>]*>(.*?)<\/a>"#
        if let regex = try? NSRegularExpression(pattern: linkPattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) {
            text = regex.stringByReplacingMatches(in: text, options: [], range: NSRange(text.startIndex..., in: text), withTemplate: "[$2]($1)")
        }

        // 5. Convert bold and italics
        let boldPattern = #"<(?:strong|b)\b[^>]*>(.*?)<\/(?:strong|b)>"#
        if let regex = try? NSRegularExpression(pattern: boldPattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) {
            text = regex.stringByReplacingMatches(in: text, options: [], range: NSRange(text.startIndex..., in: text), withTemplate: "**$1**")
        }
        let italicPattern = #"<(?:em|i)\b[^>]*>(.*?)<\/(?:em|i)>"#
        if let regex = try? NSRegularExpression(pattern: italicPattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) {
            text = regex.stringByReplacingMatches(in: text, options: [], range: NSRange(text.startIndex..., in: text), withTemplate: "*$1*")
        }

        // 6. Convert code blocks & inline code
        let preCodePattern = #"<pre\b[^>]*><code\b[^>]*>(.*?)<\/code><\/pre>"#
        if let regex = try? NSRegularExpression(pattern: preCodePattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) {
            text = regex.stringByReplacingMatches(in: text, options: [], range: NSRange(text.startIndex..., in: text), withTemplate: "\n```\n$1\n```\n")
        }
        let inlineCodePattern = #"<code\b[^>]*>(.*?)<\/code>"#
        if let regex = try? NSRegularExpression(pattern: inlineCodePattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) {
            text = regex.stringByReplacingMatches(in: text, options: [], range: NSRange(text.startIndex..., in: text), withTemplate: "`$1`")
        }

        // 7. Convert paragraphs, line breaks, blockquotes, and list items
        let brPattern = #"<br\s*\/?>"#
        if let regex = try? NSRegularExpression(pattern: brPattern, options: .caseInsensitive) {
            text = regex.stringByReplacingMatches(in: text, options: [], range: NSRange(text.startIndex..., in: text), withTemplate: "\n")
        }
        let pPattern = #"<p\b[^>]*>(.*?)<\/p>"#
        if let regex = try? NSRegularExpression(pattern: pPattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) {
            text = regex.stringByReplacingMatches(in: text, options: [], range: NSRange(text.startIndex..., in: text), withTemplate: "\n\n$1\n\n")
        }
        let liPattern = #"<li\b[^>]*>(.*?)<\/li>"#
        if let regex = try? NSRegularExpression(pattern: liPattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) {
            text = regex.stringByReplacingMatches(in: text, options: [], range: NSRange(text.startIndex..., in: text), withTemplate: "\n* $1")
        }
        let bqPattern = #"<blockquote\b[^>]*>(.*?)<\/blockquote>"#
        if let regex = try? NSRegularExpression(pattern: bqPattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) {
            text = regex.stringByReplacingMatches(in: text, options: [], range: NSRange(text.startIndex..., in: text), withTemplate: "\n\n> $1\n\n")
        }

        // 8. Strip all remaining HTML tags
        let tagPattern = #"<[^>]+>"#
        if let regex = try? NSRegularExpression(pattern: tagPattern, options: []) {
            text = regex.stringByReplacingMatches(in: text, options: [], range: NSRange(text.startIndex..., in: text), withTemplate: "")
        }

        // 9. Decode HTML entities
        text = decodeHTMLEntities(text)

        // 10. Clean noise: empty links, javascript links, social share tags
        let noisePatterns = [
            #"\*?\s*\[\s*\]\([^\)]*\)"#,
            #"\*?\s*\[[^\]]*\]\(javascript:[^\)]*\)"#,
            #"\n\s*\*\s*\n"#
        ]
        for pattern in noisePatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
                text = regex.stringByReplacingMatches(in: text, options: [], range: NSRange(text.startIndex..., in: text), withTemplate: "\n")
            }
        }

        // 11. Clean excessive newlines and whitespace
        if let multilineRegex = try? NSRegularExpression(pattern: #"\n{3,}"#) {
            text = multilineRegex.stringByReplacingMatches(in: text, options: [], range: NSRange(text.startIndex..., in: text), withTemplate: "\n\n")
        }
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // 12. Bounded character truncation
        if text.count > maxCharacters {
            let index = text.index(text.startIndex, offsetBy: maxCharacters)
            text = String(text[..<index]) + "\n\n[Content truncated...]"
        }

        return text
    }

    public static func decodeHTMLEntities(_ text: String) -> String {
        var result = text
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&#8217;", with: "'")
            .replacingOccurrences(of: "&#8216;", with: "'")
            .replacingOccurrences(of: "&#8220;", with: "\"")
            .replacingOccurrences(of: "&#8221;", with: "\"")
            .replacingOccurrences(of: "&#8211;", with: "–")
            .replacingOccurrences(of: "&#8212;", with: "—")
            .replacingOccurrences(of: "&mdash;", with: "—")
            .replacingOccurrences(of: "&ndash;", with: "–")

        // Hex and decimal numeric entities
        let entityPattern = #"&#(x?[0-9a-fA-F]+);"#
        if let regex = try? NSRegularExpression(pattern: entityPattern) {
            let matches = regex.matches(in: result, range: NSRange(result.startIndex..., in: result))
            for match in matches.reversed() {
                if let entityRange = Range(match.range, in: result),
                   let codeRange = Range(match.range(at: 1), in: result) {
                    let codeString = String(result[codeRange])
                    let codePoint: UInt32?
                    if codeString.lowercased().hasPrefix("x") {
                        codePoint = UInt32(codeString.dropFirst(), radix: 16)
                    } else {
                        codePoint = UInt32(codeString, radix: 10)
                    }
                    if let codePoint, let scalar = UnicodeScalar(codePoint) {
                        result.replaceSubrange(entityRange, with: String(scalar))
                    }
                }
            }
        }
        return result
    }
}

// MARK: - PDFDocumentReader.swift
public enum PDFDocumentReader {
    public static func extractText(from data: Data, maxCharacters: Int = 10000) -> String? {
        guard let doc = PDFDocument(data: data) else { return nil }
        var fullText = ""
        for i in 0..<doc.pageCount {
            if let pageText = doc.page(at: i)?.string {
                fullText += pageText + "\n\n"
                if fullText.count >= maxCharacters {
                    break
                }
            }
        }
        let trimmed = fullText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count > maxCharacters {
            let index = trimmed.index(trimmed.startIndex, offsetBy: maxCharacters)
            return String(trimmed[..<index]) + "\n\n[PDF truncated...]"
        }
        return trimmed.isEmpty ? nil : trimmed
    }
}

// MARK: - WebPageReader.swift
public final class WebPageReader: Sendable {
    private let session: URLSession

    public init(session: URLSession? = nil) {
        if let session {
            self.session = session
        } else {
            let config = URLSessionConfiguration.default
            config.timeoutIntervalForRequest = 8
            config.timeoutIntervalForResource = 10
            self.session = URLSession(configuration: config)
        }
    }

    public func read(url: URL, maxCharacters: Int = 4000) async throws -> String {
        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Safari/605.1.15", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw NSError(domain: "WebPageReader", code: -1, userInfo: [NSLocalizedDescriptionKey: "No HTTP response from \(url.host ?? url.absoluteString)"])
        }
        guard (200..<300).contains(http.statusCode) else {
            throw NSError(domain: "WebPageReader", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: "Failed to fetch webpage (HTTP \(http.statusCode))"])
        }

        let contentType = http.value(forHTTPHeaderField: "Content-Type")?.lowercased() ?? ""
        if contentType.contains("application/pdf") || url.pathExtension.lowercased() == "pdf" {
            if let pdfText = PDFDocumentReader.extractText(from: data, maxCharacters: maxCharacters) {
                return pdfText
            }
        }

        let html = String(decoding: data, as: UTF8.self)
        let markdown = HTMLToMarkdownConverter.convert(html: html, maxCharacters: maxCharacters)
        return markdown.isEmpty ? "The webpage contained no readable text content." : markdown
    }
}

// MARK: - WebSearchCategory.swift
public enum WebSearchCategory: String, CaseIterable, Codable, Sendable {
    case general
    case news
    case wikipedia

    public var displayName: String {
        switch self {
        case .general: return "General"
        case .news: return "News"
        case .wikipedia: return "Wikipedia"
        }
    }
}

// MARK: - WebSearchEngineType.swift
public enum WebSearchEngineType: String, CaseIterable, Codable, Sendable {
    case duckDuckGo = "duckduckgo"
    case brave = "brave"
    case aol = "aol"
    case yahoo = "yahoo"
    case wikipedia = "wikipedia"
    case news = "news"

    public var displayName: String {
        switch self {
        case .duckDuckGo: return "DuckDuckGo"
        case .brave: return "Brave"
        case .aol: return "AOL"
        case .yahoo: return "Yahoo"
        case .wikipedia: return "Wikipedia"
        case .news: return "News"
        }
    }

    public var defaultWeight: Double {
        switch self {
        case .news: return 1.3
        case .duckDuckGo: return 1.1
        case .brave: return 1.0
        case .yahoo: return 1.0
        case .aol: return 0.85
        case .wikipedia: return 0.9
        }
    }
}

// MARK: - WebSearchResult.swift
public struct WebSearchResult: Identifiable, Equatable, Hashable, Sendable {
    public let id: UUID
    public let title: String
    public let url: URL
    public let snippet: String
    public let engine: WebSearchEngineType
    public let rank: Int
    public var score: Double
    public let publishedDate: Date?

    public init(
        id: UUID = UUID(),
        title: String,
        url: URL,
        snippet: String,
        engine: WebSearchEngineType,
        rank: Int = 1,
        score: Double = 0.0,
        publishedDate: Date? = nil
    ) {
        self.id = id
        self.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        self.url = url
        self.snippet = snippet.trimmingCharacters(in: .whitespacesAndNewlines)
        self.engine = engine
        self.rank = rank
        self.score = score
        self.publishedDate = publishedDate
    }
}

// MARK: - WebSearchQuery.swift
public struct WebSearchQuery: Equatable, Sendable {
    public let rawQuery: String
    public let searchTerm: String
    public let category: WebSearchCategory
    public let siteConstraint: String?

    public var siteFilter: String? { siteConstraint }

    public init(query: String, category: WebSearchCategory = .general) {
        self.rawQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        var parsedCategory = category
        let text = self.rawQuery
        var site: String?

        var words = text.components(separatedBy: .whitespaces).filter { !$0.isEmpty }

        // Check for bangs anywhere in the words
        if let bangIndex = words.firstIndex(where: { $0.hasPrefix("!") }) {
            let bang = String(words[bangIndex].dropFirst()).lowercased()
            var matched = false
            switch bang {
            case "w", "wiki", "wikipedia":
                parsedCategory = .wikipedia
                matched = true
            case "n", "news":
                parsedCategory = .news
                matched = true
            default:
                break
            }
            if matched {
                words.remove(at: bangIndex)
            }
        } else if parsedCategory == .general {
            let lower = text.lowercased()
            if lower.contains("news") || lower.contains("today") || lower.contains("latest") || lower.contains("breaking") {
                parsedCategory = .news
            }
        }

        // Clean out hallucinated past years from news queries
        if parsedCategory == .news {
            words = words.filter { $0 != "2024" && $0 != "2025" }
        }

        // Check for site: filter
        if let siteIndex = words.firstIndex(where: { $0.lowercased().hasPrefix("site:") }) {
            let token = words[siteIndex]
            site = String(token.dropFirst(5))
        }

        self.category = parsedCategory
        self.siteConstraint = site
        self.searchTerm = words.joined(separator: " ")
    }
}

// MARK: - URLNormalizer.swift
public enum URLNormalizer {
    private static let trackingParameters: Set<String> = [
        "utm_source", "utm_medium", "utm_campaign", "utm_term", "utm_content",
        "fbclid", "gclid", "ref", "source", "spm", "_hsenc", "_hsmi",
        "mc_cid", "mc_eid", "yclid", "_openstat"
    ]

    /// Returns a clean canonical URL without tracking parameters or fragments.
    public static func normalize(_ url: URL) -> URL {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url
        }

        // Strip tracking query parameters
        if let queryItems = components.queryItems {
            let filtered = queryItems.filter { !trackingParameters.contains($0.name.lowercased()) }
            components.queryItems = filtered.isEmpty ? nil : filtered
        }

        // Normalize host (strip www.)
        if let host = components.host?.lowercased() {
            if host.hasPrefix("www.") {
                components.host = String(host.dropFirst(4))
            } else {
                components.host = host
            }
        }

        // Strip fragment (#...)
        components.fragment = nil

        // Strip trailing slash on path
        if components.path == "/" {
            components.path = ""
        } else if components.path.hasSuffix("/") {
            components.path = String(components.path.dropLast())
        }

        return components.url ?? url
    }

    /// String key for deduplicating URLs.
    public static func deduplicationKey(for url: URL) -> String {
        normalize(url).absoluteString.lowercased()
    }
}

// MARK: - URLRedirectDecoder.swift
public enum URLRedirectDecoder {
    /// Unwrap tracking and proxy redirects (DuckDuckGo uddg=, AOL/Yahoo RU=)
    public static func decode(_ rawURLString: String) -> URL? {
        let trimmed = rawURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed) else { return nil }

        // 1. DuckDuckGo: //duckduckgo.com/l/?uddg=<encoded_url>
        if url.host?.contains("duckduckgo.com") == true || trimmed.contains("/l/?uddg=") {
            if let components = URLComponents(string: trimmed),
               let uddg = components.queryItems?.first(where: { $0.name == "uddg" })?.value {
                if let decoded = uddg.removingPercentEncoding, let target = URL(string: decoded) {
                    return target
                }
            }
        }

        // 2. AOL / Yahoo: .../RU=<encoded_url>/RK=...
        if trimmed.contains("/RU=") {
            let pattern = #"/RU=([^/]+)/RK="#
            if let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)),
               let range = Range(match.range(at: 1), in: trimmed) {
                let encodedTarget = String(trimmed[range])
                if let decoded = encodedTarget.removingPercentEncoding, let target = URL(string: decoded) {
                    return target
                }
            }
        }

        // 3. Protocol relative URL: //example.com -> https://example.com
        if trimmed.hasPrefix("//") {
            return URL(string: "https:" + trimmed)
        }

        return url
    }
}

// MARK: - ConsensusScorer.swift
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

// MARK: - WebSearchCacheStore.swift
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

// MARK: - DuckDuckGoScraper.swift
public enum DuckDuckGoScraper {
    private static let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36"

    public static func search(query: String, session: URLSession = .shared) async throws -> [WebSearchResult] {
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://html.duckduckgo.com/html/?q=\(encoded)") else {
            return []
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = "q=\(encoded)&b=".data(using: .utf8)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            return []
        }

        let html = String(decoding: data, as: UTF8.self)
        return parse(html: html)
    }

    public static func parse(html: String) -> [WebSearchResult] {
        var results: [WebSearchResult] = []
        let resultPattern = #"<a\s+[^>]*class="[^"]*result__snippet[^"]*"[^>]*href="([^"]+)"[^>]*>(.*?)<\/a>"#

        // Extract using regex
        guard let snippetRegex = try? NSRegularExpression(pattern: resultPattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return []
        }

        let matches = snippetRegex.matches(in: html, options: [], range: NSRange(html.startIndex..., in: html))
        var rank = 1

        for match in matches.prefix(10) {
            guard let hrefRange = Range(match.range(at: 1), in: html),
                  let snippetRange = Range(match.range(at: 2), in: html) else { continue }

            let rawHref = String(html[hrefRange])
            let rawSnippet = String(html[snippetRange])

            guard let targetURL = URLRedirectDecoder.decode(rawHref) else { continue }
            let cleanSnippet = HTMLToMarkdownConverter.decodeHTMLEntities(rawSnippet).trimmingCharacters(in: .whitespacesAndNewlines)
            let hostTitle = targetURL.host ?? targetURL.absoluteString

            results.append(
                WebSearchResult(
                    title: hostTitle,
                    url: targetURL,
                    snippet: cleanSnippet,
                    engine: .duckDuckGo,
                    rank: rank
                )
            )
            rank += 1
        }
        return results
    }
}

// MARK: - BraveSearchScraper.swift
public enum BraveSearchScraper {
    private static let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Safari/605.1.15"

    public static func search(query: String, session: URLSession = .shared) async throws -> [WebSearchResult] {
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://search.brave.com/search?q=\(encoded)") else {
            return []
        }

        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            return []
        }

        let html = String(decoding: data, as: UTF8.self)
        return parse(html: html)
    }

    public static func parse(html: String) -> [WebSearchResult] {
        var results: [WebSearchResult] = []
        let pattern = #"<div\s+[^>]*class="[^"]*snippet[^"]*"[^>]*data-type="web"[^>]*>.*?<a\s+[^>]*href="([^"]+)"[^>]*>.*?<span[^>]*class="[^"]*title[^"]*"[^>]*>(.*?)<\/span>.*?<\/a>.*?<div\s+[^>]*class="[^"]*snippet-description[^"]*"[^>]*>(.*?)<\/div>"#

        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return []
        }

        let matches = regex.matches(in: html, options: [], range: NSRange(html.startIndex..., in: html))
        var rank = 1

        for match in matches.prefix(10) {
            guard let urlRange = Range(match.range(at: 1), in: html),
                  let titleRange = Range(match.range(at: 2), in: html),
                  let descRange = Range(match.range(at: 3), in: html) else { continue }

            let rawURL = String(html[urlRange])
            let rawTitle = String(html[titleRange])
            let rawDesc = String(html[descRange])

            guard let targetURL = URL(string: rawURL) else { continue }
            let cleanTitle = HTMLToMarkdownConverter.decodeHTMLEntities(rawTitle.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression))
            let cleanSnippet = HTMLToMarkdownConverter.decodeHTMLEntities(rawDesc.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression))

            results.append(
                WebSearchResult(
                    title: cleanTitle,
                    url: targetURL,
                    snippet: cleanSnippet,
                    engine: .brave,
                    rank: rank
                )
            )
            rank += 1
        }
        return results
    }
}

// MARK: - YahooSearchScraper.swift
public enum YahooSearchScraper {
    private static let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36"

    public static func search(query: String, session: URLSession = .shared) async throws -> [WebSearchResult] {
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://search.yahoo.com/search?p=\(encoded)&nojs=1") else {
            return []
        }

        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            return []
        }

        let html = String(decoding: data, as: UTF8.self)
        return parse(html: html)
    }

    public static func parse(html: String) -> [WebSearchResult] {
        var results: [WebSearchResult] = []
        let pattern = #"<h3\s+[^>]*class="[^"]*title[^"]*"[^>]*><a\s+[^>]*href="([^"]+)"[^>]*>(.*?)<\/a><\/h3>.*?<div\s+[^>]*class="[^"]*compText[^"]*"[^>]*>(.*?)<\/div>"#

        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return []
        }

        let matches = regex.matches(in: html, options: [], range: NSRange(html.startIndex..., in: html))
        var rank = 1

        for match in matches.prefix(10) {
            guard let urlRange = Range(match.range(at: 1), in: html),
                  let titleRange = Range(match.range(at: 2), in: html),
                  let descRange = Range(match.range(at: 3), in: html) else { continue }

            let rawURL = String(html[urlRange])
            let rawTitle = String(html[titleRange])
            let rawDesc = String(html[descRange])

            guard let targetURL = URLRedirectDecoder.decode(rawURL) else { continue }
            let cleanTitle = HTMLToMarkdownConverter.decodeHTMLEntities(rawTitle.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression))
            let cleanSnippet = HTMLToMarkdownConverter.decodeHTMLEntities(rawDesc.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression))

            results.append(
                WebSearchResult(
                    title: cleanTitle,
                    url: targetURL,
                    snippet: cleanSnippet,
                    engine: .yahoo,
                    rank: rank
                )
            )
            rank += 1
        }
        return results
    }
}

// MARK: - AolSearchScraper.swift
public enum AolSearchScraper {
    private static let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36"

    public static func search(query: String, session: URLSession = .shared) async throws -> [WebSearchResult] {
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://search.aol.com/aol/search?q=\(encoded)&nojs=1") else {
            return []
        }

        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            return []
        }

        let html = String(decoding: data, as: UTF8.self)
        return parse(html: html)
    }

    public static func parse(html: String) -> [WebSearchResult] {
        var results: [WebSearchResult] = []
        let pattern = #"<h3\s+[^>]*class="[^"]*title[^"]*"[^>]*><a\s+[^>]*href="([^"]+)"[^>]*>(.*?)<\/a><\/h3>.*?<div\s+[^>]*class="[^"]*compText[^"]*"[^>]*>(.*?)<\/div>"#

        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return []
        }

        let matches = regex.matches(in: html, options: [], range: NSRange(html.startIndex..., in: html))
        var rank = 1

        for match in matches.prefix(10) {
            guard let urlRange = Range(match.range(at: 1), in: html),
                  let titleRange = Range(match.range(at: 2), in: html),
                  let descRange = Range(match.range(at: 3), in: html) else { continue }

            let rawURL = String(html[urlRange])
            let rawTitle = String(html[titleRange])
            let rawDesc = String(html[descRange])

            guard let targetURL = URLRedirectDecoder.decode(rawURL) else { continue }
            let cleanTitle = HTMLToMarkdownConverter.decodeHTMLEntities(rawTitle.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression))
            let cleanSnippet = HTMLToMarkdownConverter.decodeHTMLEntities(rawDesc.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression))

            results.append(
                WebSearchResult(
                    title: cleanTitle,
                    url: targetURL,
                    snippet: cleanSnippet,
                    engine: .aol,
                    rank: rank
                )
            )
            rank += 1
        }
        return results
    }
}

// MARK: - WikipediaEngine.swift
public enum WikipediaEngine {
    public static func search(query: String, session: URLSession = .shared) async throws -> [WebSearchResult] {
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://en.wikipedia.org/w/api.php?action=query&list=search&srsearch=\(encoded)&format=json&utf8=1") else {
            return []
        }

        var request = URLRequest(url: url)
        request.setValue("Tinycast-Search/1.0", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            return []
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let queryObj = json["query"] as? [String: Any],
              let searchArr = queryObj["search"] as? [[String: Any]] else {
            return []
        }

        var results: [WebSearchResult] = []
        var rank = 1

        for item in searchArr.prefix(5) {
            guard let title = item["title"] as? String,
                  let rawSnippet = item["snippet"] as? String,
                  let pageURL = URL(string: "https://en.wikipedia.org/wiki/\(title.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? title)") else {
                continue
            }

            let cleanSnippet = HTMLToMarkdownConverter.decodeHTMLEntities(
                rawSnippet.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            )

            results.append(
                WebSearchResult(
                    title: "\(title) - Wikipedia",
                    url: pageURL,
                    snippet: cleanSnippet,
                    engine: .wikipedia,
                    rank: rank
                )
            )
            rank += 1
        }
        return results
    }
}

// MARK: - NewsRSSEngine.swift
public enum NewsRSSEngine {
    public static func search(query: String, session: URLSession = .shared) async throws -> [WebSearchResult] {
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://news.google.com/rss/search?q=\(encoded)&hl=en-US&gl=US&ceid=US:en") else {
            return []
        }

        var request = URLRequest(url: url)
        request.setValue("Tinycast-News/1.0", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            return []
        }

        let xml = String(decoding: data, as: UTF8.self)
        return parse(xml: xml)
    }

    public static func parse(xml: String) -> [WebSearchResult] {
        var results: [WebSearchResult] = []
        let itemPattern = #"<item>.*?<title>(.*?)<\/title>.*?<link>(.*?)<\/link>.*?(?:<pubDate>(.*?)<\/pubDate>)?.*?(?:<description>(.*?)<\/description>)?.*?<\/item>"#

        guard let regex = try? NSRegularExpression(pattern: itemPattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return []
        }

        let matches = regex.matches(in: xml, options: [], range: NSRange(xml.startIndex..., in: xml))
        var rank = 1

        for match in matches.prefix(8) {
            guard let titleRange = Range(match.range(at: 1), in: xml),
                  let linkRange = Range(match.range(at: 2), in: xml) else { continue }

            let rawTitle = String(xml[titleRange])
            let rawLink = String(xml[linkRange]).trimmingCharacters(in: .whitespacesAndNewlines)

            guard let url = URL(string: rawLink) else { continue }

            var snippet = ""
            if match.numberOfRanges > 4, let descRange = Range(match.range(at: 4), in: xml) {
                let rawDesc = String(xml[descRange])
                snippet = HTMLToMarkdownConverter.decodeHTMLEntities(
                    rawDesc.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
                ).trimmingCharacters(in: .whitespacesAndNewlines)
            }

            let cleanTitle = HTMLToMarkdownConverter.decodeHTMLEntities(rawTitle).trimmingCharacters(in: .whitespacesAndNewlines)

            results.append(
                WebSearchResult(
                    title: cleanTitle,
                    url: url,
                    snippet: snippet.isEmpty ? cleanTitle : snippet,
                    engine: .news,
                    rank: rank
                )
            )
            rank += 1
        }
        return results
    }
}

// MARK: - WebSearchAggregator.swift
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
