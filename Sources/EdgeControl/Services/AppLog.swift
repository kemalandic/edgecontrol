import Foundation
import os

/// Central logging for the app.
///
/// EdgeControl had no shared logger: failures were swallowed by `try?` at the
/// point they happened, which made "my layout reset itself" impossible to
/// diagnose from a user's report. These categories show up in Console.app under
/// the `ai.pakslab.edgecontrol` subsystem.
public enum AppLog {
    private static let subsystem = "ai.pakslab.edgecontrol"

    /// Reading and writing anything the user would notice losing — layout,
    /// plugin storage, calibration, widget snapshots.
    public static let persistence = Logger(subsystem: subsystem, category: "Persistence")
    /// Plugin discovery, installation, removal.
    public static let plugins = Logger(subsystem: subsystem, category: "Plugins")
    /// CI/CD accounts and providers.
    public static let cicd = Logger(subsystem: subsystem, category: "CICD")
}

extension AppLog {
    /// Runs a throwing write and logs the failure instead of discarding it.
    ///
    /// Replaces the `try? data.write(…)` pattern: the caller still cannot
    /// recover, but the failure stops being invisible.
    ///
    /// - Returns: `true` when the operation succeeded.
    @discardableResult
    public static func attempt(
        _ what: @autoclosure () -> String,
        log: Logger = AppLog.persistence,
        _ body: () throws -> Void
    ) -> Bool {
        do {
            try body()
            return true
        } catch {
            // Evaluated into a local: the logger's interpolation is an escaping
            // autoclosure and cannot capture the non-escaping parameter.
            let description = what()
            log.error("\(description, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }
}
