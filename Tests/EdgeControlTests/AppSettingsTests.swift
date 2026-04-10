import XCTest
@testable import EdgeControl

final class AppSettingsTests: XCTestCase {
    func testDefaultSettings() {
        let settings = AppSettings()
        XCTAssertTrue(settings.kioskMode)
        XCTAssertFalse(settings.debugMode)
        XCTAssertNil(settings.selectedDisplayName)
    }
}
