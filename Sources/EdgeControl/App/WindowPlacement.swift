import AppKit
import SwiftUI

public enum WindowPlacement {
    /// Place a window per the kiosk-mode / display configuration.
    ///
    /// Returns true when placed. In strict kiosk mode a named target must
    /// be connected; otherwise the window is hidden until it returns.
    /// A named target remains eligible when it becomes NSScreen.main,
    /// which follows keyboard focus. With no preference, use a non-main screen.
    @MainActor
    @discardableResult
    public static func configure(
        _ window: NSWindow?,
        display: DisplayDescriptor?,
        kioskMode: Bool,
        preferredDisplayName: String? = nil,
        strictMonitorAffinity: Bool = false,
        allowSystemPanels: Bool = false
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
                if let name = preferredDisplayName ?? display?.name {
                    // NSScreen.main follows keyboard focus; the named display
                    // remains valid even when its dashboard becomes key.
                    return NSScreen.screens.first { $0.localizedName == name }
                }
                return NSScreen.screens.first { $0 != NSScreen.main }
            }
            // Non-strict (default): named match → first non-main → main.
            return NSScreen.screens.first { screen in
                guard let displayName = display?.name else { return false }
                return screen.localizedName == displayName
            } ?? NSScreen.screens.first { $0 != NSScreen.main } ?? NSScreen.main
        }()

        guard let screen = targetScreen else {
            window.orderOut(nil)
            return false
        }

        window.styleMask = [.borderless]
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
