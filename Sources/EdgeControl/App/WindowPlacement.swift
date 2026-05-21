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
