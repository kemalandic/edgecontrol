import AppKit

/// Decides when the dashboard hands its real accessibility tree to assistive
/// tools (see KioskHostingView for why it otherwise doesn't: building it costs
/// several milliseconds per frame while dragging).
///
/// VoiceOver and Switch Control have public flags. Voice Control and Full
/// Keyboard Access don't; macOS records them in the com.apple.Accessibility
/// preferences as `CommandAndControlEnabled` and `FullKeyboardAccessEnabled`.
/// Those keys are undocumented, so "Always Available to Accessibility Tools"
/// in Settings is the fallback if a future macOS renames them.
@MainActor
enum AccessibilityExposure {
    /// Mirrors GlobalSettings.alwaysExposeAccessibility.
    static var alwaysExpose = false
    /// Tests force a result without changing system settings.
    static var testOverride: Bool?

    static let preferencesDomain = "com.apple.Accessibility"
    static let undocumentedKeys = ["FullKeyboardAccessEnabled", "CommandAndControlEnabled"]

    static var isNeeded: Bool {
        if let testOverride { return testOverride }
        if alwaysExpose { return true }
        let workspace = NSWorkspace.shared
        if workspace.isVoiceOverEnabled || workspace.isSwitchControlEnabled { return true }
        return keyboardOrVoiceControlOn
    }

    /// True when any of the given preference values reads as on.
    nonisolated static func anyEnabled(_ values: [Any?]) -> Bool {
        values.contains { ($0 as? NSNumber)?.boolValue == true }
    }

    /// Accessibility clients query constantly; re-read the preferences at
    /// most every two seconds.
    private static var cached: (value: Bool, at: TimeInterval)?
    private static var keyboardOrVoiceControlOn: Bool {
        let now = ProcessInfo.processInfo.systemUptime
        if let cached, now - cached.at < 2 { return cached.value }
        let domain = preferencesDomain as CFString
        CFPreferencesAppSynchronize(domain)
        let value = anyEnabled(undocumentedKeys.map { CFPreferencesCopyAppValue($0 as CFString, domain) })
        cached = (value, now)
        return value
    }
}
