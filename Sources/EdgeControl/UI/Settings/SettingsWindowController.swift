import AppKit
import SwiftUI

/// Manages a separate NSWindow for Settings.
/// Settings opens as a standalone window so the dashboard remains visible.
/// Clicking gear always brings it to front — creates new window only if needed.
@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    static let shared = SettingsWindowController()

    private var window: NSWindow?

    /// Exposed so file panels can attach as sheets. The settings window sits
    /// above the status-bar level; a detached NSSavePanel/NSOpenPanel orders
    /// at the much lower modal-panel level and pops under it, while a sheet
    /// is a child window and always renders over its parent.
    var settingsWindow: NSWindow? { window }

    private override init() {
        super.init()
    }

    private var pluginManager: PluginManager?
    private var model: AppModel?
    private var layoutEngine: LayoutEngine?
    private var registry: WidgetRegistry?

    func configure(model: AppModel, layoutEngine: LayoutEngine, registry: WidgetRegistry, pluginManager: PluginManager) {
        self.model = model
        self.layoutEngine = layoutEngine
        self.registry = registry
        self.pluginManager = pluginManager
    }

    func show(model: AppModel? = nil, layoutEngine: LayoutEngine? = nil, registry: WidgetRegistry? = nil, pluginManager: PluginManager? = nil) {
        if let m = model { self.model = m }
        if let le = layoutEngine { self.layoutEngine = le }
        if let r = registry { self.registry = r }
        if let pm = pluginManager { self.pluginManager = pm }

        guard let model = self.model, let layoutEngine = self.layoutEngine, let registry = self.registry else { return }

        // If window exists and is still valid, just bring to front
        if let win = window {
            win.level = .normal
            moveOffKioskScreen(win)
            win.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        // Create new window
        var settingsView = SettingsView()
            .environmentObject(model)
            .environmentObject(layoutEngine)
            .environmentObject(registry)
        let rootView: AnyView
        if let pm = self.pluginManager {
            rootView = AnyView(settingsView.environmentObject(pm))
        } else {
            rootView = AnyView(settingsView)
        }

        let hosting = NSHostingController(rootView: rootView)
        let win = NSWindow(contentViewController: hosting)
        win.title = "EdgeControl Settings"
        win.styleMask = [.titled, .closable, .resizable]
        win.setContentSize(NSSize(width: 1130, height: 755))
        win.center()
        win.isReleasedWhenClosed = false
        win.level = .normal
        win.delegate = self
        moveOffKioskScreen(win)
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        window = win
    }

    /// At normal level this window is buried whenever it sits on the kiosk
    /// display (the kiosk deliberately stays above the status-bar level), and
    /// center() centers on whichever screen has focus — often the kiosk after
    /// touch use. Keep the window on a screen where it can actually be seen.
    private func moveOffKioskScreen(_ win: NSWindow) {
        let kioskScreen = NSApp.windows.first { $0 is KioskWindow }?.screen
        guard let kioskScreen,
              win.screen == kioskScreen || win.screen == nil,
              let target = NSScreen.screens.first(where: { $0 != kioskScreen })
        else { return }
        let size = win.frame.size
        let v = target.visibleFrame
        win.setFrameOrigin(NSPoint(
            x: v.midX - size.width / 2,
            y: v.midY - size.height / 2
        ))
    }

    func close() {
        window?.close()
        window = nil
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        // Clear reference so next show() creates a fresh window
        window = nil
    }
}
