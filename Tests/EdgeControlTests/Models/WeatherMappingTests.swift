import Foundation
import Testing
@testable import EdgeControl

/// The fixture is a real Open-Meteo response, captured 2026-09-20 for the
/// coordinates in the vendor's own documentation, with the exact query the app
/// sends. Invented JSON would only test what this author believes the API
/// returns.
@Suite("Weather mapping")
struct WeatherMappingTests {

    private func recordedResponse() throws -> OpenMeteoResponse {
        let url = try #require(
            Bundle(for: StubTransport.self).url(forResource: "weather-berlin-5day", withExtension: "json"),
            "fixture missing from the test bundle"
        )
        return try JSONDecoder().decode(OpenMeteoResponse.self, from: Data(contentsOf: url))
    }

    private func daily(times: [String], codes: [Int], highs: [Double], lows: [Double]) -> OpenMeteoResponse {
        let json: [String: Any] = [
            "current": [
                "temperature_2m": 12.3, "relative_humidity_2m": 60,
                "weather_code": 0, "wind_speed_10m": 9.4, "is_day": 1,
            ],
            "daily": [
                "time": times, "weather_code": codes,
                "temperature_2m_max": highs, "temperature_2m_min": lows,
            ],
        ]
        let data = try! JSONSerialization.data(withJSONObject: json)
        return try! JSONDecoder().decode(OpenMeteoResponse.self, from: data)
    }

    // MARK: the recorded response

    @Test("the recorded response decodes and maps")
    func recordedDecodes() throws {
        let response = try recordedResponse()
        let current = WeatherMapping.current(from: response)

        #expect(current.humidity >= 0 && current.humidity <= 100)
        #expect(current.conditionText.isEmpty == false)
        #expect(current.symbolName.isEmpty == false)
        #expect(WeatherMapping.forecast(from: response).count == 5, "the query asks for five days")
    }

    @Test("every forecast day carries a description and a symbol")
    func forecastIsComplete() throws {
        for day in WeatherMapping.forecast(from: try recordedResponse()) {
            #expect(day.date.isEmpty == false)
            #expect(day.conditionText.isEmpty == false)
            #expect(day.symbolName.isEmpty == false)
            #expect(day.highTemp >= day.lowTemp, "\(day.date): high below low")
        }
    }

    // MARK: what a partial response does

    /// The reason this moved out of the service. It walked the dates while
    /// indexing three other arrays, so a response whose arrays disagreed —
    /// truncated, throttled, mid-change — would have trapped rather than shown
    /// a shorter forecast.
    @Test("a day the arrays do not all cover is dropped, not crashed on")
    func mismatchedArraysAreTruncated() {
        let response = daily(
            times: ["2026-09-20", "2026-09-21", "2026-09-22"],
            codes: [0, 1, 2],
            highs: [20, 21],          // one short
            lows: [10]                // two short
        )
        let forecast = WeatherMapping.forecast(from: response)
        #expect(forecast.count == 1)
        #expect(forecast.first?.date == "2026-09-20")
    }

    @Test("empty daily arrays yield an empty forecast")
    func emptyForecast() {
        let forecast = WeatherMapping.forecast(from: daily(times: [], codes: [], highs: [], lows: []))
        #expect(forecast.isEmpty)
    }

    /// Dates present with nothing to describe them is the same case from the
    /// other side: nothing to show rather than a crash.
    @Test("dates without readings yield nothing")
    func datesWithoutReadings() {
        let response = daily(times: ["2026-09-20"], codes: [], highs: [], lows: [])
        #expect(WeatherMapping.forecast(from: response).isEmpty)
    }

    @Test("is_day drives the day and night symbol")
    func isDayDrivesSymbol() {
        let json: (Int) -> OpenMeteoResponse = { isDay in
            let data = try! JSONSerialization.data(withJSONObject: [
                "current": [
                    "temperature_2m": 12.0, "relative_humidity_2m": 50,
                    "weather_code": 0, "wind_speed_10m": 5.0, "is_day": isDay,
                ],
                "daily": ["time": [], "weather_code": [], "temperature_2m_max": [], "temperature_2m_min": []],
            ])
            return try! JSONDecoder().decode(OpenMeteoResponse.self, from: data)
        }
        #expect(WeatherMapping.current(from: json(1)).isDay)
        #expect(WeatherMapping.current(from: json(0)).isDay == false)
        #expect(WeatherMapping.current(from: json(1)).symbolName
                != WeatherMapping.current(from: json(0)).symbolName)
    }
}
