import XCTest
@testable import EdgeControl

final class LayoutConfigTests: XCTestCase {
    /// Guards the defaults that ship when a user has no saved layout.
    func testGlobalSettingsDefaults() {
        let settings = GlobalSettings()
        XCTAssertTrue(settings.kioskMode)
        XCTAssertFalse(settings.launchAtLogin)
        XCTAssertFalse(settings.debugMode)
        XCTAssertNil(settings.selectedDisplayName)
    }

    /// A round-trip guard: settings must survive encode/decode unchanged,
    /// because LayoutStore persists them as JSON.
    func testGlobalSettingsCodableRoundTrip() throws {
        var settings = GlobalSettings()
        settings.kioskMode = false
        settings.selectedDisplayName = "XENEON EDGE"
        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(GlobalSettings.self, from: data)
        XCTAssertFalse(decoded.kioskMode)
        XCTAssertEqual(decoded.selectedDisplayName, "XENEON EDGE")
    }
}
