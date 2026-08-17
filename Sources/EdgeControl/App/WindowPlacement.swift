import AppKit
import SwiftUI

public enum WindowPlacement {
    /// Place a window per the kiosk-mode / display configuration.
    ///
    /// Returns true if a target screen was found and the window was
    /// placed; false if no eligible target exists (caller can decide
    /// whether to hide the window or accept the no-op).
    ///
    /// `strictMonitorAffinity` (default false → preserves existing
    /// behavior): when true and kiosk mode is on, the placement
    /// pipeline NEVER falls back to NSScreen.main and only accepts a
    /// non-main screen. If a target display is named, it must match a
    /// non-main screen exactly; if no name is set, the first non-main
    /// screen wins. If neither yields a hit (the configured target is
    /// asleep / unplugged, or the system is single-monitor), this
    /// returns false WITHOUT touching the window — useful when the
    /// caller wants to keep the window parked off-screen rather than
    /// surfacing it on the main display.
    @MainActor
    @discardableResult
    public static func configure(
        _ window: NSWindow?,
        display: DisplayDescriptor?,
        kioskMode: Bool,
        strictMonitorAffinity: Bool = false
    ) -> Bool {
        guard let window else { return false }

        if !kioskMode {
            // Window mode: standard resizable window, no screen affinity.
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            window.level = .normal
            window.collectionBehavior = []
            return true
        }

        let targetScreen: NSScreen? = {
            if strictMonitorAffinity {
                // Strict: only non-main screens are eligible, full stop.
                // No silent fallback to main.
                let nonMain = NSScreen.screens.filter { $0 != NSScreen.main }
                if let displayName = display?.name {
                    return nonMain.first { $0.localizedName == displayName }
                }
                return nonMain.first
            }
            // Non-strict (default): named match → first non-main → main.
            return NSScreen.screens.first { screen in
                guard let displayName = display?.name else { return false }
                return screen.localizedName == displayName
            } ?? NSScreen.screens.first { $0 != NSScreen.main } ?? NSScreen.main
        }()

        guard let screen = targetScreen else { return false }

        window.styleMask = [.borderless]
        window.level = .statusBar
        window.collectionBehavior = [.canJoinAllSpaces, .stationary]
        window.setFrame(screen.frame, display: true)
        window.orderFrontRegardless()
        return true
    }
}

/// Borderless window that accepts key status — required for mouse/touch event handling in kiosk mode.
class KioskWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// Hosts the dashboard and keeps its SwiftUI tree out of the accessibility
/// hierarchy — the whole dashboard is one opaque group to assistive clients.
///
/// SwiftUI builds accessibility elements for a hosting view lazily, the first
/// time any client walks or hit-tests it, and from then on it re-derives the
/// attachments for every gesture-bearing element on every render. A full page
/// is ~400 elements, which is 4–5 ms per frame; a drag renders per pointer
/// event and turned from smooth into seconds behind the finger. Clients that
/// do this are everywhere and invisible to the user: text grabbers query the
/// element under the pointer on every mouse-up, hotkey navigators scan the
/// front app, window managers enumerate windows. Never handing out children
/// keeps the tree from ever being materialised, and the widgets remain
/// operable through the Settings window.
final class KioskHostingView<Content: View>: NSHostingView<Content> {
    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .group }
    override func accessibilityLabel() -> String? { "EdgeControl dashboard" }
    override func accessibilityChildren() -> [Any]? { nil }
    override func accessibilityChildrenInNavigationOrder() -> [any NSAccessibilityElementProtocol]? { nil }
    override func accessibilityHitTest(_ point: NSPoint) -> Any? { self }
    override var accessibilityFocusedUIElement: Any? { nil }
}

struct WindowAccessor: NSViewRepresentable {
    let callback: (NSWindow?) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            callback(view.window)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            callback(nsView.window)
        }
    }
}
