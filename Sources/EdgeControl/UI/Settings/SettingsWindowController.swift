import AppKit
import SwiftUI

/// Manages a separate NSWindow for Settings.
/// Settings opens as a standalone window so the dashboard remains visible.
/// Clicking gear always brings it to front — creates new window only if needed.
@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    static let shared = SettingsWindowController()

    private var window: NSWindow?

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
            win.level = NSWindow.Level(NSWindow.Level.statusBar.rawValue + 1)
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
        win.setContentSize(NSSize(width: 700, height: 500))
        win.center()
        win.isReleasedWhenClosed = false
        win.level = NSWindow.Level(NSWindow.Level.statusBar.rawValue + 1)
        win.delegate = self
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        window = win
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
