import Foundation
import Testing

@testable import EdgeControl

/// This suite is the guard itself. The app bundle is the test host, so `main()`
/// runs for real during a test run: it loads the layout and migrates notes. If
/// `AppSupport` ever stops redirecting, a test run quietly rewrites the
/// dashboard and the notes of whoever is running it — which happened once,
/// before the redirect existed, and left no trace that anything had.
@Suite("Application support directory")
struct AppSupportTests {

    private var realNotesDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("EdgeControl/Notes", isDirectory: true)
    }

    @Test("A test run is pointed away from the real directory")
    func testsGetAScratchDirectory() {
        #expect(AppSupport.isRunningTests)

        let path = AppSupport.directory.path
        #expect(path.contains("EdgeControl-Tests"))
        #expect(
            !path.contains("Application Support/EdgeControl"),
            "a test run must not resolve to the directory the app ships against"
        )
    }

    /// The rest of the suite injects a directory into the stores it builds.
    /// This one deliberately does not: the default is what the app takes, and
    /// the default is what went wrong.
    @Test("A store built the way the app builds it writes to the scratch directory")
    func defaultStoreStaysOutOfTheRealDirectory() {
        let probe = "app-support-probe"
        let store = NoteStore()
        defer { store.delete(id: probe) }

        store.save(id: probe, rtfBase64: "", plainText: "probe")

        let scratch = AppSupport.directory.appendingPathComponent("Notes/\(probe).txt")
        #expect(FileManager.default.fileExists(atPath: scratch.path))
        #expect(
            !FileManager.default.fileExists(atPath: realNotesDirectory.appendingPathComponent("\(probe).txt").path),
            "a test just wrote into the real notes directory"
        )
    }
}
