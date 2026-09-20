import Foundation

/// Runs AppleScript in EdgeControlScriptRunner, the background-only helper
/// embedded at `Contents/Helpers`.
///
/// Not /usr/bin/osascript: it checks in with the window server as a foreground
/// app once it sends an Apple event, so polling through it every five seconds
/// flashed an icon in the Dock. Not NSAppleScript in this process either: it is
/// main-thread only, and a query can hold that thread for most of a second.
///
/// The helper is our child process, so the system holds EdgeControl responsible
/// for its Apple events — Automation permission is still granted to, and asked
/// for by, EdgeControl.
public enum AppleScriptRunner {
    public enum Failure: Error, Equatable {
        /// The helper is not in the bundle: a build that did not embed it.
        case helperMissing
        case launchFailed
        /// Still running at the deadline, so it was killed.
        case timedOut
        /// The script ran and raised an error.
        case scriptFailed(status: Int32)
    }

    public static var helperURL: URL {
        Bundle.main.bundleURL.appendingPathComponent(
            "Contents/Helpers/EdgeControlScriptRunner.app/Contents/MacOS/EdgeControlScriptRunner"
        )
    }

    /// Runs `source` and returns what the script returned, trimmed.
    ///
    /// Blocks the calling thread until the script finishes or `timeout` passes,
    /// so call it off the main actor.
    public static func run(
        _ source: String,
        timeout: TimeInterval = 4.0,
        helper: URL = helperURL
    ) -> Result<String, Failure> {
        guard FileManager.default.isExecutableFile(atPath: helper.path) else {
            AppLog.media.error("AppleScript helper missing at \(helper.path, privacy: .public)")
            return .failure(.helperMissing)
        }

        let pipe = Pipe()
        let process = Process()
        process.executableURL = helper
        process.arguments = [source]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            AppLog.media.error("AppleScript helper failed to launch: \(error.localizedDescription, privacy: .public)")
            return .failure(.launchFailed)
        }
        guard awaitExit(process, timeout: timeout) else { return .failure(.timedOut) }
        guard process.terminationStatus == 0 else {
            return .failure(.scriptFailed(status: process.terminationStatus))
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return .success(String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// Waits for `process`, killing it at the deadline; false means it had to be
    /// killed. A bare `waitUntilExit()` blocks for as long as the target app
    /// takes to answer, and that is unbounded while an Automation prompt sits
    /// unanswered.
    private static func awaitExit(_ process: Process, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.1)
        }
        if process.isRunning {
            process.terminate()
            return false
        }
        return true
    }
}
