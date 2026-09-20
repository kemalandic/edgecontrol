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
        // Drain the pipe while the helper runs, not after it exits. A pipe holds
        // about 64 KiB; a script whose result is larger blocks writing, so it
        // never exits, so a reader that waits for exit first waits forever and
        // the deadline kills the helper with its answer still in the buffer.
        // The Safari query concatenates a line per media tab, which is exactly
        // the case that gets big.
        let handle = pipe.fileHandleForReading
        let buffer = OutputBuffer()
        let group = DispatchGroup()
        DispatchQueue.global(qos: .utility).async(group: group) {
            buffer.store(handle.readDataToEndOfFile())
        }

        guard awaitExit(process, timeout: timeout) else {
            // Terminating closes the write end, so the reader returns; bound the
            // wait anyway rather than trade one hang for another.
            _ = group.wait(timeout: .now() + 1)
            return .failure(.timedOut)
        }
        group.wait()

        guard process.terminationStatus == 0 else {
            return .failure(.scriptFailed(status: process.terminationStatus))
        }
        return .success(
            String(decoding: buffer.take(), as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    /// Waits for `process`, killing it at the deadline; false means it had to be
    /// killed. A bare `waitUntilExit()` blocks for as long as the target app
    /// takes to answer, and that is unbounded while an Automation prompt sits
    /// unanswered.
    private static func awaitExit(_ process: Process, timeout: TimeInterval) -> Bool {
        // Monotonic. A wall-clock deadline stops bounding anything the moment
        // NTP steps the clock backwards, and bounding the wait is the whole job.
        let deadline = ContinuousClock.now.advanced(by: .seconds(timeout))
        while process.isRunning && ContinuousClock.now < deadline {
            Thread.sleep(forTimeInterval: 0.1)
        }
        if process.isRunning {
            process.terminate()
            return false
        }
        return true
    }
}

/// Carries the helper's stdout from the reader queue back to the caller.
private final class OutputBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()

    func store(_ value: Data) {
        lock.lock(); defer { lock.unlock() }
        data = value
    }

    func take() -> Data {
        lock.lock(); defer { lock.unlock() }
        return data
    }
}
