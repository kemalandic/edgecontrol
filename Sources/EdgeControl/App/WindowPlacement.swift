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
        strictMonitorAffinity: Bool = false,
        allowSystemPanels: Bool = false
    ) -> Bool {
        guard let window else { return false }

        // The non-activating bit is part of the window's identity (see
        // KioskWindow) and must survive style changes. Assign only on change:
        // this runs on every dashboard update.
        let keep = window.styleMask.intersection(.nonactivatingPanel)
        func setStyle(_ style: NSWindow.StyleMask) {
            let desired = style.union(keep)
            if window.styleMask != desired { window.styleMask = desired }
        }

        if !kioskMode {
            // Window mode: standard resizable window, no screen affinity.
            setStyle([.titled, .closable, .miniaturizable, .resizable])
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

        setStyle([.borderless])
        // Paste-class panels present at the menu-bar level (24) on the key
        // window's screen; at .statusBar (25) the kiosk buries them
        // invisibly. One notch below lets them through, at the cost of the
        // menu bar being able to draw over the dashboard.
        window.level =
            allowSystemPanels
            ? NSWindow.Level(NSWindow.Level.mainMenu.rawValue - 1)
            : .statusBar
        window.collectionBehavior = [.canJoinAllSpaces, .stationary]
        window.setFrame(screen.frame, display: true)
        window.orderFrontRegardless()
        return true
    }
}

/// The dashboard window: a panel that accepts key status (needed for mouse
/// and touch handling when borderless) and, by default, never activates the
/// app, so clicking or tapping it leaves focus on the display you're using.
/// See DashboardFocus. Whether it activates is fixed at creation; changing the
/// setting replaces the window.
class KioskWindow: NSPanel {
    let neverActivates: Bool

    init(contentRect: NSRect, neverActivates: Bool) {
        self.neverActivates = neverActivates
        var style: NSWindow.StyleMask = [.titled, .closable, .miniaturizable, .resizable]
        if neverActivates { style.insert(.nonactivatingPanel) }
        super.init(contentRect: contentRect, styleMask: style, backing: .buffered, defer: false)
        identifier = DashboardFocus.windowIdentifier
        // Panels hide when their app is inactive and float by default; the
        // dashboard must do neither.
        hidesOnDeactivate = false
        isFloatingPanel = false
        // Become key only for controls that need typing (text views/fields).
        becomesKeyOnlyIfNeeded = neverActivates
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { !neverActivates }
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
/// keeps the tree from ever being materialised.
///
/// The exception is a person using VoiceOver, Switch Control, Voice Control
/// or Full Keyboard Access (or the "Always Available to Accessibility Tools"
/// setting): for them the dashboard's real elements (widget cards, buttons)
/// are exposed, at that per-frame cost. See AccessibilityExposure.
final class KioskHostingView<Content: View>: NSHostingView<Content> {
    private var exposesTree: Bool { AccessibilityExposure.isNeeded }
    override func isAccessibilityElement() -> Bool { exposesTree ? super.isAccessibilityElement() : true }
    override func accessibilityRole() -> NSAccessibility.Role? { exposesTree ? super.accessibilityRole() : .group }
    override func accessibilityLabel() -> String? { "EdgeControl dashboard" }
    override func accessibilityChildren() -> [Any]? { exposesTree ? super.accessibilityChildren() : nil }
    override func accessibilityChildrenInNavigationOrder() -> [any NSAccessibilityElementProtocol]? {
        exposesTree ? super.accessibilityChildrenInNavigationOrder() : nil
    }
    override func accessibilityHitTest(_ point: NSPoint) -> Any? {
        exposesTree ? super.accessibilityHitTest(point) : self
    }
    override var accessibilityFocusedUIElement: Any? { exposesTree ? super.accessibilityFocusedUIElement : nil }
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
