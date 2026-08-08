import Foundation

/// Which units the dashboard displays in.
///
/// Conversion is display-only. The SMC reports Celsius and the forecast API is
/// asked for Celsius and km/h, and both stay that way everywhere else — the
/// history buffers, the graph normalisation and the colour thresholds all keep
/// working on the same numbers whichever system is showing.
public enum UnitSystem: String, Codable, CaseIterable, Sendable {
    case metric
    case imperial

    public var displayName: String {
        switch self {
        case .metric: "Metric"
        case .imperial: "Imperial"
        }
    }

    public var detail: String {
        switch self {
        case .metric: "°C, km/h"
        case .imperial: "°F, mph"
        }
    }

    /// What the user's region already uses, so a fresh install reads correctly
    /// without anyone opening Settings. The UK counts as metric here: it gives
    /// weather in Celsius, which is most of what this switch drives.
    public static var localeDefault: UnitSystem {
        Locale.current.measurementSystem == .us ? .imperial : .metric
    }

    // MARK: - Temperature

    public func temperature(fromCelsius celsius: Double) -> Double {
        switch self {
        case .metric: celsius
        case .imperial: celsius * 9 / 5 + 32
        }
    }

    public var temperatureSymbol: String {
        switch self {
        case .metric: "°C"
        case .imperial: "°F"
        }
    }

    /// `62°` — for gauges and chips where the surrounding label already says
    /// what is being measured and the scale is obvious from context.
    public func degrees(fromCelsius celsius: Double) -> String {
        String(format: "%.0f°", temperature(fromCelsius: celsius))
    }

    /// `62°C` — where the reading stands alone and the unit has to be explicit.
    public func temperatureText(fromCelsius celsius: Double) -> String {
        String(format: "%.0f%@", temperature(fromCelsius: celsius), temperatureSymbol)
    }

    /// A *difference* between two temperatures rather than a reading. The two
    /// scales share no zero point, so only the ratio carries over: run a
    /// 7-degree swing through the reading formula and it comes out as 45.
    public func temperatureDifference(fromCelsius delta: Double) -> Double {
        switch self {
        case .metric: delta
        case .imperial: delta * 9 / 5
        }
    }

    // MARK: - Wind

    public func windSpeed(fromKilometresPerHour kmh: Double) -> Double {
        switch self {
        case .metric: kmh
        case .imperial: kmh / 1.609_344
        }
    }

    public var windSpeedSymbol: String {
        switch self {
        case .metric: "km/h"
        case .imperial: "mph"
        }
    }

    public func windSpeedText(fromKilometresPerHour kmh: Double) -> String {
        String(format: "%.0f %@", windSpeed(fromKilometresPerHour: kmh), windSpeedSymbol)
    }
}
