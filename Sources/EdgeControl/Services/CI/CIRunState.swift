import Foundation

/// Normalised run outcome, shared with the sandboxed widget extension via
/// `WidgetData`. Kept in its own file so the extension imports only this
/// enum rather than the whole CI layer.
public enum CIRunState: String, Equatable, Sendable, Codable {
    case queued, running, success, failure, cancelled, skipped, unknown

    /// True while the run is still expected to change. Drives sort priority —
    /// active runs float to the top regardless of age.
    public var isActive: Bool {
        self == .running || self == .queued
    }
}
