import CoreLocation
import Foundation
import Network

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
    public let temperature: Double  // Celsius
    public let humidity: Int  // 0-100
    public let windSpeed: Double  // km/h
    public let weatherCode: Int
    public let isDay: Bool
    public let conditionText: String
    public let symbolName: String  // SF Symbol
}

public struct DayForecast: Identifiable, Equatable, Sendable {
    public var id: String { date }
    public let date: String  // "2026-04-04"
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
    /// Set when the forecast isn't for where you are: location was refused
    /// or unavailable, so it's for your last known place, or London.
    @Published public private(set) var locationNote: String?
    /// When the shown forecast was fetched; older readings stay on screen
    /// (with a note) while a refresh fails.
    @Published public private(set) var updatedAt: Date?

    private let locationManager = LocationProvider()
    private var timer: Timer?
    private var fetchTask: Task<Void, Never>?
    private var retryTask: Task<Void, Never>?
    private var pathMonitor: NWPathMonitor?
    private var failures = 0
    /// Between start() and stop(). Callbacks already queued when it stopped
    /// (network, timer, retry) check it and do nothing.
    private var running = false

    public init() {}

    /// After a failed fetch, try again sooner than the 15-minute refresh:
    /// 30 s, 2 min, then 5 min; after that the regular refresh takes over.
    nonisolated static func retryDelay(afterFailures failures: Int) -> Duration? {
        switch failures {
        case 1: .seconds(30)
        case 2: .seconds(120)
        case 3: .seconds(300)
        default: nil
        }
    }

    public func start() {
        stop()
        running = true
        // Allowing location in the prompt or in System Settings refreshes
        // the forecast straight away, not at the next 15-minute refresh.
        locationManager.onAuthorizationChange = { [weak self] in
            guard let self, self.running, self.locationNote != nil else { return }
            self.fetch()
        }
        fetch()
        // Refresh every 15 minutes
        timer = Timer.scheduledTimer(withTimeInterval: 900, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.fetch()
            }
        }
        // A minute either side of a 15-minute forecast refresh is free.
        timer?.tolerance = 60
        // Back online after a failure (wake before Wi-Fi joins, a dropout):
        // fetch straight away rather than waiting for the next retry.
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            guard path.status == .satisfied else { return }
            Task { @MainActor [weak self] in
                guard let self, self.running, self.error != nil || self.current == nil else { return }
                self.fetch()
            }
        }
        monitor.start(queue: .main)
        pathMonitor = monitor
    }

    public func stop() {
        running = false
        timer?.invalidate()
        timer = nil
        fetchTask?.cancel()
        fetchTask = nil
        retryTask?.cancel()
        retryTask = nil
        pathMonitor?.cancel()
        pathMonitor = nil
    }

    private static let lastLocationKey = "weather.lastLocation"

    private func fetch() {
        guard running else { return }
        fetchTask?.cancel()
        retryTask?.cancel()
        fetchTask = Task { [weak self] in
            guard let self else { return }
            let (location, note) = await self.resolveLocation()
            guard !Task.isCancelled else { return }
            do {
                let lat = location.coordinate.latitude
                let lon = location.coordinate.longitude
                let urlString =
                    "https://api.open-meteo.com/v1/forecast?latitude=\(lat)&longitude=\(lon)&current=temperature_2m,relative_humidity_2m,weather_code,wind_speed_10m,is_day&daily=weather_code,temperature_2m_max,temperature_2m_min&timezone=auto&forecast_days=5"
                guard let url = URL(string: urlString) else {
                    self.error = "Invalid URL"
                    return
                }
                let (data, _) = try await URLSession.shared.data(from: url)
                let response = try JSONDecoder().decode(OpenMeteoResponse.self, from: data)
                guard !Task.isCancelled else { return }
                self.current = WeatherMapping.current(from: response)
                self.dailyForecast = WeatherMapping.forecast(from: response)
                self.updatedAt = Date()
                // Published with the forecast it describes, never by a
                // request that was cancelled.
                self.locationNote = note
                self.error = nil
                self.failures = 0
            } catch {
                guard !Task.isCancelled else { return }
                self.error = error.localizedDescription
                self.failures += 1
                if let delay = Self.retryDelay(afterFailures: self.failures) {
                    self.retryTask = Task { [weak self] in
                        try? await Task.sleep(for: delay)
                        guard !Task.isCancelled else { return }
                        self?.fetch()
                    }
                }
            }
        }
    }

    /// Where you are; failing that, where you were last time; failing that,
    /// London. Says which in `locationNote`.
    private func resolveLocation() async -> (CLLocation, note: String?) {
        if let location = try? await locationManager.currentLocation(timeout: .seconds(15)) {
            if !Task.isCancelled {
                UserDefaults.standard.set(
                    [location.coordinate.latitude, location.coordinate.longitude], forKey: Self.lastLocationKey)
            }
            return (location, nil)
        }
        if let saved = UserDefaults.standard.array(forKey: Self.lastLocationKey) as? [Double], saved.count == 2 {
            return (
                CLLocation(latitude: saved[0], longitude: saved[1]),
                "Location unavailable: showing your last known location."
            )
        }
        return (
            CLLocation(latitude: 51.5074, longitude: -0.1278),
            "Location unavailable: showing London. Allow Location Services for EdgeControl Media in System Settings → Privacy & Security."
        )
    }

    // MARK: - WMO Weather Code Mapping

    /// Pure lookup — nonisolated so the mapping can use it off the main
    /// actor.
    nonisolated static func weatherDescription(code: Int) -> String {
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

    /// Pure lookup — nonisolated so the mapping can use it off the main
    /// actor.
    nonisolated static func weatherSymbol(code: Int, isDay: Bool) -> String {
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

/// One location request at a time, on the main thread: CLLocationManager
/// calls its delegate on the thread it was created on (main), and the
/// pending continuation is only touched there.
@MainActor
final class LocationProvider: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<CLLocation, Error>?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    /// A recent fix, or a new one within `timeout` (CoreLocation can stay
    /// silent, e.g. with Wi-Fi off).
    func currentLocation(timeout: Duration) async throws -> CLLocation {
        if let location = manager.location, location.timestamp.timeIntervalSinceNow > -300 {
            return location
        }
        finish(.failure(CancellationError()))
        manager.requestWhenInUseAuthorization()
        let timeoutTask = Task { [weak self] in
            try? await Task.sleep(for: timeout)
            guard !Task.isCancelled else { return }
            self?.finish(.failure(CLError(.locationUnknown)))
        }
        defer { timeoutTask.cancel() }
        // A cancelled fetch ends its location request too.
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                manager.requestLocation()
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.finish(.failure(CancellationError())) }
        }
    }

    /// Resumes the pending request exactly once.
    private func finish(_ result: Result<CLLocation, Error>) {
        guard let continuation else { return }
        self.continuation = nil
        continuation.resume(with: result)
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.first else { return }
        MainActor.assumeIsolated { finish(.success(location)) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        MainActor.assumeIsolated { finish(.failure(error)) }
    }

    /// Called when you allow (or deny) location, in the prompt or Settings.
    var onAuthorizationChange: (() -> Void)?

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        MainActor.assumeIsolated { onAuthorizationChange?() }
    }
}
