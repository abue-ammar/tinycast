import Foundation

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
