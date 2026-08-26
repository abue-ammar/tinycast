import CoreLocation
import Foundation

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
