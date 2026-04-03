import CoreLocation
import Foundation

// MARK: - Open-Meteo Weather Models

public struct OpenMeteoResponse: Codable {
    let current: OpenMeteoCurrent
    let daily: OpenMeteoDaily
}

public struct OpenMeteoCurrent: Codable {
    let temperature2m: Double
    let relativeHumidity2m: Int
    let weatherCode: Int
    let windSpeed10m: Double
    let isDay: Int

    enum CodingKeys: String, CodingKey {
        case temperature2m = "temperature_2m"
        case relativeHumidity2m = "relative_humidity_2m"
        case weatherCode = "weather_code"
        case windSpeed10m = "wind_speed_10m"
        case isDay = "is_day"
    }
}

public struct OpenMeteoDaily: Codable {
    let time: [String]
    let weatherCode: [Int]
    let temperature2mMax: [Double]
    let temperature2mMin: [Double]

    enum CodingKeys: String, CodingKey {
        case time
        case weatherCode = "weather_code"
        case temperature2mMax = "temperature_2m_max"
        case temperature2mMin = "temperature_2m_min"
    }
}

// MARK: - App-facing Weather Models

public struct CurrentWeatherData: Equatable, Sendable {
    public let temperature: Double      // Celsius
    public let humidity: Int            // 0-100
    public let windSpeed: Double        // km/h
    public let weatherCode: Int
    public let isDay: Bool
    public let conditionText: String
    public let symbolName: String       // SF Symbol
}

public struct DayForecast: Identifiable, Equatable, Sendable {
    public var id: String { date }
    public let date: String             // "2026-04-04"
    public let weatherCode: Int
    public let highTemp: Double
    public let lowTemp: Double
    public let conditionText: String
    public let symbolName: String
}

// MARK: - Weather Service (Open-Meteo)

@MainActor
public final class WeatherDataService: ObservableObject {
    @Published public var current: CurrentWeatherData?
    @Published public var dailyForecast: [DayForecast] = []
    @Published public var error: String?

    private let locationManager = LocationProvider()
    private var timer: Timer?

    public init() {}

    public func start() {
        stop()
        fetch()
        // Refresh every 15 minutes
        timer = Timer.scheduledTimer(withTimeInterval: 900, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.fetch()
            }
        }
    }

    public func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func fetch() {
        Task {
            do {
                let location: CLLocation
                do {
                    location = try await locationManager.currentLocation()
                } catch {
                    // Fallback: Istanbul
                    location = CLLocation(latitude: 41.0082, longitude: 28.9784)
                }

                let lat = location.coordinate.latitude
                let lon = location.coordinate.longitude
                let urlString = "https://api.open-meteo.com/v1/forecast?latitude=\(lat)&longitude=\(lon)&current=temperature_2m,relative_humidity_2m,weather_code,wind_speed_10m,is_day&daily=weather_code,temperature_2m_max,temperature_2m_min&timezone=auto&forecast_days=5"

                guard let url = URL(string: urlString) else {
                    self.error = "Invalid URL"
                    return
                }

                let (data, _) = try await URLSession.shared.data(from: url)
                let response = try JSONDecoder().decode(OpenMeteoResponse.self, from: data)

                self.current = CurrentWeatherData(
                    temperature: response.current.temperature2m,
                    humidity: response.current.relativeHumidity2m,
                    windSpeed: response.current.windSpeed10m,
                    weatherCode: response.current.weatherCode,
                    isDay: response.current.isDay == 1,
                    conditionText: Self.weatherDescription(code: response.current.weatherCode),
                    symbolName: Self.weatherSymbol(code: response.current.weatherCode, isDay: response.current.isDay == 1)
                )

                self.dailyForecast = zip(response.daily.time.indices, response.daily.time).map { index, date in
                    let code = response.daily.weatherCode[index]
                    return DayForecast(
                        date: date,
                        weatherCode: code,
                        highTemp: response.daily.temperature2mMax[index],
                        lowTemp: response.daily.temperature2mMin[index],
                        conditionText: Self.weatherDescription(code: code),
                        symbolName: Self.weatherSymbol(code: code, isDay: true)
                    )
                }

                self.error = nil
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    // MARK: - WMO Weather Code Mapping

    static func weatherDescription(code: Int) -> String {
        switch code {
        case 0: return "Clear"
        case 1: return "Mostly Clear"
        case 2: return "Partly Cloudy"
        case 3: return "Overcast"
        case 45, 48: return "Foggy"
        case 51: return "Light Drizzle"
        case 53: return "Drizzle"
        case 55: return "Heavy Drizzle"
        case 61: return "Light Rain"
        case 63: return "Rain"
        case 65: return "Heavy Rain"
        case 66, 67: return "Freezing Rain"
        case 71: return "Light Snow"
        case 73: return "Snow"
        case 75: return "Heavy Snow"
        case 77: return "Snow Grains"
        case 80: return "Light Showers"
        case 81: return "Showers"
        case 82: return "Heavy Showers"
        case 85: return "Snow Showers"
        case 86: return "Heavy Snow Showers"
        case 95: return "Thunderstorm"
        case 96, 99: return "Thunderstorm + Hail"
        default: return "Unknown"
        }
    }

    static func weatherSymbol(code: Int, isDay: Bool) -> String {
        switch code {
        case 0: return isDay ? "sun.max.fill" : "moon.stars.fill"
        case 1: return isDay ? "sun.min.fill" : "moon.fill"
        case 2: return isDay ? "cloud.sun.fill" : "cloud.moon.fill"
        case 3: return "cloud.fill"
        case 45, 48: return "cloud.fog.fill"
        case 51, 53, 55: return "cloud.drizzle.fill"
        case 61, 63, 80, 81: return "cloud.rain.fill"
        case 65, 82: return "cloud.heavyrain.fill"
        case 66, 67: return "cloud.sleet.fill"
        case 71, 73, 85: return "cloud.snow.fill"
        case 75, 77, 86: return "snowflake"
        case 95: return "cloud.bolt.fill"
        case 96, 99: return "cloud.bolt.rain.fill"
        default: return "questionmark.circle"
        }
    }
}

// MARK: - Location Provider

final class LocationProvider: NSObject, CLLocationManagerDelegate, @unchecked Sendable {
    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<CLLocation, Error>?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    func currentLocation() async throws -> CLLocation {
        if let location = manager.location,
           location.timestamp.timeIntervalSinceNow > -300 {
            return location
        }
        manager.requestWhenInUseAuthorization()
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            manager.requestLocation()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        if let location = locations.first {
            continuation?.resume(returning: location)
            continuation = nil
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        continuation?.resume(throwing: error)
        continuation = nil
    }
}
