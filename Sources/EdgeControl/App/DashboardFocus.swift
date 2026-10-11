import AppKit

/// Keeps the dashboard from taking focus away from where you're working.
///
/// A newly launched app opens its first window on the display that holds
/// keyboard focus. When the dashboard was the active app's key window, that
/// was the dashboard's display, so apps opened behind the kiosk. Measured
/// with a probe app on a four-display setup: with the dashboard's app in the
/// background, or merely holding the keyboard as a non-activating panel, a
/// new app's centred window opens on the display you're using.
///
/// So the dashboard is a non-activating panel, and the keyboard is borrowed
/// only for what needs it: text fields (until you click elsewhere), edit mode
/// and calibration (until they end). File pickers need the app genuinely
/// active, briefly. The "Dashboard never takes focus" setting turns all of
/// this off and restores the old behaviour.
@MainActor
enum DashboardFocus {
    /// Mirrors GlobalSettings.dashboardNeverTakesFocus.
    static var neverTakesFocus = true
    /// Set on the dashboard window so this file needs no other app types.
    static let windowIdentifier = NSUserInterfaceItemIdentifier("EdgeControlDashboard")
    static let settingChanged = Notification.Name("EdgeControlDashboardFocusSettingChanged")

    /// Modes that keep the keyboard until they end ("edit", "calibration").
    private(set) static var holders: Set<String> = []

    static var dashboard: NSWindow? { NSApp.windows.first { $0.identifier == windowIdentifier } }

    /// Gives the dashboard the keyboard. With the setting on it becomes the
    /// key window without the app becoming active, so the menu bar and the
    /// display new apps open on stay where you are.
    static func takeKeyboard(_ window: NSWindow? = nil, holder: String? = nil) {
        if let holder { holders.insert(holder) }
        guard let window = window ?? dashboard else { return }
        if neverTakesFocus {
            window.makeKey()
        } else {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
        }
    }

    /// Ends a mode that held the keyboard and hands focus back once no mode
    /// still needs it.
    static func returnKeyboard(holder: String) {
        holders.remove(holder)
        releaseIfIdle()
    }

    /// Hands keyboard focus back to the app you were using, unless a mode
    /// still needs it or another EdgeControl window (Settings) is open.
    static func releaseIfIdle() {
        guard neverTakesFocus, holders.isEmpty else { return }
        // Settings or the Quick Capture box are things you're using; leave them
        // focused. Child windows (the sticky-note format bar) belong to the
        // dashboard and don't count.
        let otherWindowOpen = NSApp.windows.contains {
            $0.isVisible && $0.identifier != windowIdentifier && $0.canBecomeKey && $0.parent == nil
        }
        guard !otherWindowOpen else { return }
        if NSApp.isActive {
            NSApp.deactivate()
        } else if dashboard?.isKeyWindow == true {
            NSWorkspace.shared.frontmostApplication?.activate()
        }
    }

    /// For system UI that requires an active app (the application picker).
    /// Pair with `releaseIfIdle()` when it closes.
    static func activateForSystemSheet(_ window: NSWindow) {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}
