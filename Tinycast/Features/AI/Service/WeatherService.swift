import Foundation

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
