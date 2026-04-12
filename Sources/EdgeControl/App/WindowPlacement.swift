import AppKit
import SwiftUI

public enum WindowPlacement {
    @MainActor public static func configure(
        _ window: NSWindow?,
        display: DisplayDescriptor?,
        kioskMode: Bool
    ) {
        guard let window else { return }

        if !kioskMode {
            // Window mode: standard resizable window
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            window.level = .normal
            window.collectionBehavior = []
            return
        }

        // Kiosk mode: full-screen borderless on selected display
        let targetScreen = NSScreen.screens.first { screen in
            guard let displayName = display?.name else { return false }
            return screen.localizedName == displayName
        } ?? NSScreen.screens.first { $0 != NSScreen.main } ?? NSScreen.main

        guard let screen = targetScreen else { return }

        window.styleMask = [.borderless]
        window.level = .statusBar
        window.collectionBehavior = [.canJoinAllSpaces, .stationary]
        window.setFrame(screen.frame, display: true)
        window.orderFrontRegardless()
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
