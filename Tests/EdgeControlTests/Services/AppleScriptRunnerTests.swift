import Foundation
import Testing
@testable import EdgeControl

/// `AppleScriptRunner` runs every Now Playing query and media command through
/// the helper embedded in the app bundle. These tests run hosted inside
/// EdgeControl.app, so they exercise the helper the build actually embedded
/// rather than a stand-in. None of the scripts target another application, so
/// no Automation permission is involved.
@Suite("AppleScript runner")
struct AppleScriptRunnerTests {

    /// The whole point of the helper: osascript put an icon in the Dock on every
    /// poll. A helper that loses LSBackgroundOnly brings that straight back.
    @Test("Helper is embedded in the app bundle as a background-only app")
    func helperIsBackgroundOnly() throws {
        let helperApp = Bundle.main.bundleURL
            .appendingPathComponent("Contents/Helpers/EdgeControlScriptRunner.app")
        let info = try #require(Bundle(url: helperApp)?.infoDictionary)

        #expect(info["LSBackgroundOnly"] as? Bool == true)
        #expect(FileManager.default.isExecutableFile(atPath: AppleScriptRunner.helperURL.path))
    }

    @Test("Returns what the script returns")
    func returnsResult() {
        #expect(AppleScriptRunner.run(#"return "merhaba""#) == .success("merhaba"))
    }

    /// Track titles come back through the helper's stdout; Turkish titles are
    /// the everyday case, not an edge case.
    @Test("Round-trips non-ASCII text")
    func roundTripsUnicode() {
        #expect(
            AppleScriptRunner.run(#"return "Saçına Çiçek Taksam — ğüşıöç""#)
                == .success("Saçına Çiçek Taksam — ğüşıöç"))
    }

    @Test("A script that raises an error is reported as failed")
    func scriptErrorFails() {
        #expect(AppleScriptRunner.run(#"error "boom""#) == .failure(.scriptFailed(status: 1)))
    }

    /// An unanswered Automation prompt or a hung browser blocks the script for
    /// as long as the target takes. The deadline is what keeps a poll bounded.
    @Test("A script that outlives the deadline is killed")
    func timeoutKills() {
        let started = Date()
        let result = AppleScriptRunner.run("delay 10", timeout: 0.5)

        #expect(result == .failure(.timedOut))
        #expect(Date().timeIntervalSince(started) < 3)
    }

    /// A pipe holds about 64 KiB. Reading it only after the helper exits
    /// deadlocks on anything larger: the helper blocks writing, never exits, and
    /// the deadline kills it with the answer still in the buffer. The Safari
    /// query grows with the number of open media tabs, so this is the realistic
    /// shape of it, not a synthetic limit.
    @Test("Survives a result larger than the pipe buffer")
    func resultLargerThanPipeBuffer() {
        // 10 * 2^14 = 163,840 characters, comfortably past the buffer.
        let script = """
            set chunk to "0123456789"
            repeat 14 times
                set chunk to chunk & chunk
            end repeat
            return chunk
            """
        let result = AppleScriptRunner.run(script, timeout: 10)

        switch result {
        case .success(let text):
            #expect(text.count == 163_840, "got \(text.count) characters")
        case .failure(let failure):
            Issue.record("expected the full result, got \(failure)")
        }
    }

    @Test("A missing helper fails instead of launching anything")
    func missingHelperFails() {
        let nowhere = URL(fileURLWithPath: "/nonexistent/EdgeControlScriptRunner")
        #expect(AppleScriptRunner.run(#"return "x""#, helper: nowhere) == .failure(.helperMissing))
    }
}
