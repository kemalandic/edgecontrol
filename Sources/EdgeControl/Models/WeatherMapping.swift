import Foundation

/// Turning an Open-Meteo response into what the widget shows.
///
/// The daily forecast arrives as parallel arrays — one of dates, one of codes,
/// one of highs, one of lows — and the mapping walked the dates while indexing
/// the other three. Nothing guarantees a remote API returns them the same
/// length, and an Array subscript past the end traps, so a truncated or partial
/// response would have crashed the app instead of showing a shorter forecast.
public enum WeatherMapping {

    public static func current(from response: OpenMeteoResponse) -> CurrentWeatherData {
        let code = response.current.weatherCode
        let isDay = response.current.isDay == 1
        return CurrentWeatherData(
            temperature: response.current.temperature2m,
            humidity: response.current.relativeHumidity2m,
            windSpeed: response.current.windSpeed10m,
            weatherCode: code,
            isDay: isDay,
            conditionText: WeatherDataService.weatherDescription(code: code),
            symbolName: WeatherDataService.weatherSymbol(code: code, isDay: isDay)
        )
    }

    /// One entry per day the response can fully describe. Days the arrays do
    /// not all cover are dropped rather than guessed at or crashed on.
    public static func forecast(from response: OpenMeteoResponse) -> [DayForecast] {
        let daily = response.daily
        let count = min(
            daily.time.count,
            daily.weatherCode.count,
            daily.temperature2mMax.count,
            daily.temperature2mMin.count
        )
        guard count > 0 else { return [] }

        return (0..<count).map { index in
            let code = daily.weatherCode[index]
            return DayForecast(
                date: daily.time[index],
                weatherCode: code,
                highTemp: daily.temperature2mMax[index],
                lowTemp: daily.temperature2mMin[index],
                conditionText: WeatherDataService.weatherDescription(code: code),
                symbolName: WeatherDataService.weatherSymbol(code: code, isDay: true)
            )
        }
    }
}
