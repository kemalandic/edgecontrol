import Foundation

/// The one directory the app keeps its files in.
///
/// It exists for the second branch. Under `xcodebuild test` the app bundle is
/// the test host, so `main()` runs for real: it loads the dashboard, and since
/// notes moved into a store of their own it also migrates them. Against the
/// default directory that means a test run rewrites the layout and the notes
/// of whoever is running it — which it did, once, before this was here.
///
/// Tests get a scratch directory under the system temporary folder, which the
/// OS sweeps up on its own.
public enum AppSupport {

    public static let directory: URL = {
        guard !isRunningTests else {
            return FileManager.default.temporaryDirectory
                .appendingPathComponent("EdgeControl-Tests", isDirectory: true)
        }
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return support.appendingPathComponent("EdgeControl", isDirectory: true)
    }()

    /// Set by XCTest in the host process's environment. Swift Testing runs
    /// inside the same host, so this covers both.
    static var isRunningTests: Bool {
        let environment = ProcessInfo.processInfo.environment
        return environment["XCTestConfigurationFilePath"] != nil
            || environment["XCTestBundlePath"] != nil
    }
}
