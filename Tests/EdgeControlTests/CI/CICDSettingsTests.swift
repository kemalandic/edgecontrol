import XCTest
@testable import EdgeControl

final class CICDSettingsTests: XCTestCase {
    private func suite() -> UserDefaults {
        UserDefaults(suiteName: "test-\(UUID().uuidString)")!
    }

    func testDefaults() {
        let s = CICDSettings.default
        XCTAssertEqual(s.pollInterval, 30)
        XCTAssertEqual(s.activityWindowDays, 14)
        XCTAssertTrue(s.pinnedRepositories.isEmpty)
        XCTAssertTrue(s.hiddenRepositories.isEmpty)
    }

    /// The bug this type exists to prevent: the pickers appeared to work but
    /// every value reset on the next launch.
    func testSettingsSurviveReload() {
        let defaults = suite()
        var s = CICDSettings.default
        s.pollInterval = 120
        s.activityWindowDays = 7
        s.pinnedRepositories = [CIRepositoryRef(host: "git.example.dev", fullName: "acme/lb")]
        s.hiddenRepositories = [CIRepositoryRef(host: "github.com", fullName: "acme/noisy")]
        s.save(to: defaults)

        XCTAssertEqual(CICDSettings.load(from: defaults), s)
    }

    /// The lists were once unqualified `owner/name` strings. An unreadable
    /// list must not take the interval and window down with it.
    func testLegacyUnqualifiedListsAreDroppedWithoutLosingOtherSettings() throws {
        let defaults = suite()
        let legacy = #"""
        {
          "pollInterval": 90,
          "activityWindowDays": 30,
          "pinnedRepositories": ["acme/old"],
          "hiddenRepositories": ["acme/noisy"]
        }
        """#
        defaults.set(Data(legacy.utf8), forKey: "cicd.settings")

        let loaded = CICDSettings.load(from: defaults)
        XCTAssertEqual(loaded.pollInterval, 90)
        XCTAssertEqual(loaded.activityWindowDays, 30)
        XCTAssertTrue(loaded.pinnedRepositories.isEmpty)
        XCTAssertTrue(loaded.hiddenRepositories.isEmpty)
    }

    /// A pin names one host. Applying it everywhere polled a Forgejo
    /// repository against github.com.
    func testRepositoryRefIsHostQualified() {
        let a = CIRepositoryRef(host: "github.com", fullName: "acme/app")
        let b = CIRepositoryRef(host: "git.example.dev", fullName: "acme/app")
        XCTAssertNotEqual(a, b)
        XCTAssertEqual(Set([a, b]).count, 2)
        XCTAssertEqual(b.displayName, "git.example.dev · acme/app")
    }

    func testMissingValueFallsBackToDefaults() {
        XCTAssertEqual(CICDSettings.load(from: suite()), .default)
    }

    /// A corrupt preference must not leave the widget unusable.
    func testCorruptValueFallsBackToDefaults() {
        let defaults = suite()
        defaults.set(Data("not json".utf8), forKey: "cicd.settings")
        XCTAssertEqual(CICDSettings.load(from: defaults), .default)
    }

    @MainActor
    func testServiceLoadsAndPersistsThroughItsSettings() {
        let defaults = suite()
        let store = CIAccountStore(defaults: defaults, secrets: InMemorySecretStore())

        let service = CICDService(accountStore: store, defaults: defaults)
        XCTAssertEqual(service.settings, .default)

        service.settings.pollInterval = 60
        service.settings.pinnedRepositories.insert(CIRepositoryRef(host: "github.com", fullName: "acme/keep"))

        // A fresh service must see the same values — this is what "the picker
        // actually did something" means.
        let reloaded = CICDService(accountStore: store, defaults: defaults)
        XCTAssertEqual(reloaded.settings.pollInterval, 60)
        XCTAssertEqual(
            reloaded.settings.pinnedRepositories,
            [CIRepositoryRef(host: "github.com", fullName: "acme/keep")]
        )
    }
}
