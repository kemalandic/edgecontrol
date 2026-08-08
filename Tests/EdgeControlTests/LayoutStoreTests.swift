import XCTest
@testable import EdgeControl

/// LayoutStore holds the only copy of the user's dashboard arrangement, so these
/// cover the paths where that copy can go missing rather than the happy path.
final class LayoutStoreTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("LayoutStoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
        directory = nil
        try super.tearDownWithError()
    }

    private var layoutURL: URL { directory.appendingPathComponent("layout.json") }
    private var backupURL: URL { directory.appendingPathComponent("layout.json.corrupt") }

    func testFirstLaunchWritesTheGeneratedDefaults() {
        let document = LayoutStore(directory: directory).load()

        XCTAssertFalse(document.pages.isEmpty)
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: layoutURL.path),
            "the defaults must reach disk, or the next launch regenerates them again"
        )
    }

    func testAnExistingLayoutIsReturnedAsSaved() {
        let store = LayoutStore(directory: directory)
        var document = store.load()
        document.pages = [PageConfig(name: "Only Page", order: 0)]
        store.save(document)

        let reloaded = LayoutStore(directory: directory).load()

        XCTAssertEqual(reloaded.pages.map(\.name), ["Only Page"])
    }

    /// The regression this file exists for. An unreadable layout used to be
    /// replaced with defaults in place, which is how an arrangement disappears
    /// leaving nothing behind to look at. The read can also fail for reasons
    /// that have nothing to do with the contents.
    func testAnUnreadableLayoutIsKeptRatherThanOverwritten() throws {
        try Data("not json".utf8).write(to: layoutURL)

        let document = LayoutStore(directory: directory).load()

        XCTAssertFalse(document.pages.isEmpty, "the app still needs a usable layout")
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: backupURL.path),
            "the unreadable file must survive"
        )
        XCTAssertEqual(
            try String(contentsOf: backupURL, encoding: .utf8),
            "not json",
            "the surviving copy must be the original bytes"
        )
    }

    /// Quarantine deliberately keeps one generation: the first failure is the
    /// copy closest to the last good state, so a later one must not bury it.
    func testASecondFailureDoesNotReplaceTheFirstBackup() throws {
        try Data("original".utf8).write(to: layoutURL)
        _ = LayoutStore(directory: directory).load()

        try Data("later garbage".utf8).write(to: layoutURL)
        _ = LayoutStore(directory: directory).load()

        XCTAssertEqual(try String(contentsOf: backupURL, encoding: .utf8), "original")
    }
}
