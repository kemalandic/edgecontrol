import XCTest
@testable import EdgeControl

final class UnitSystemTests: XCTestCase {
    func testMetricLeavesReadingsAlone() {
        XCTAssertEqual(UnitSystem.metric.temperature(fromCelsius: 62), 62)
        XCTAssertEqual(UnitSystem.metric.windSpeed(fromKilometresPerHour: 14), 14)
        XCTAssertEqual(UnitSystem.metric.temperatureText(fromCelsius: 62), "62°C")
        XCTAssertEqual(UnitSystem.metric.windSpeedText(fromKilometresPerHour: 14), "14 km/h")
    }

    func testImperialConvertsReadings() {
        XCTAssertEqual(UnitSystem.imperial.temperature(fromCelsius: 0), 32)
        XCTAssertEqual(UnitSystem.imperial.temperature(fromCelsius: 100), 212)
        XCTAssertEqual(UnitSystem.imperial.temperatureText(fromCelsius: 62), "144°F")
        XCTAssertEqual(UnitSystem.imperial.windSpeedText(fromKilometresPerHour: 16.09344), "10 mph")
    }

    /// A difference has no zero point to shift. Running a 7-degree swing through
    /// the reading formula would report it as 45, which is the trap this guards.
    func testATemperatureDifferenceScalesWithoutTheOffset() {
        XCTAssertEqual(UnitSystem.imperial.temperatureDifference(fromCelsius: 7), 12.6, accuracy: 0.001)
        XCTAssertEqual(UnitSystem.metric.temperatureDifference(fromCelsius: 7), 7)
        XCTAssertNotEqual(
            UnitSystem.imperial.temperatureDifference(fromCelsius: 7),
            UnitSystem.imperial.temperature(fromCelsius: 7)
        )
    }

    func testTheCompactFormReportsNoUnit() {
        XCTAssertEqual(UnitSystem.metric.degrees(fromCelsius: 62), "62°")
        XCTAssertEqual(UnitSystem.imperial.degrees(fromCelsius: 62), "144°")
    }

    /// Settings written before this option existed have no `units` key, and must
    /// keep decoding — a throw here reaches LayoutStore as an unreadable file.
    func testSettingsWithoutAUnitsKeyStillDecode() throws {
        let json = """
        {"kioskMode": false, "launchAtLogin": true, "debugMode": false}
        """
        let settings = try JSONDecoder().decode(GlobalSettings.self, from: Data(json.utf8))

        XCTAssertFalse(settings.kioskMode)
        XCTAssertTrue(settings.launchAtLogin)
        XCTAssertEqual(settings.units, .localeDefault)
    }

    func testTheChosenUnitsSurviveARoundTrip() throws {
        var settings = GlobalSettings()
        settings.units = .imperial

        let decoded = try JSONDecoder().decode(
            GlobalSettings.self, from: JSONEncoder().encode(settings)
        )

        XCTAssertEqual(decoded.units, .imperial)
    }

    /// The desktop widget shares this payload. An older snapshot carries no
    /// units at all and has to keep decoding rather than blanking the widget.
    func testASnapshotWithoutUnitsStillDecodes() throws {
        let withUnits = WidgetData(cpuTemp: 62, unitSystem: .imperial)
        // The pair the app actually uses: the shared coders agree on a date
        // strategy that a default JSONEncoder does not.
        let encoded = try JSONEncoder.widgetEncoder.encode(withUnits)
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        object.removeValue(forKey: "unitSystem")
        let stripped = try JSONSerialization.data(withJSONObject: object)

        let decoded = try XCTUnwrap(WidgetData.decode(from: stripped))

        XCTAssertNil(decoded.unitSystem)
        XCTAssertEqual(decoded.cpuTemp, 62)
    }
}
