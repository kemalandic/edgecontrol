import AppKit
import Darwin
import SwiftUI

@MainActor
final class DashboardWindowController {
    private var window: NSWindow?

    func show(
        model: AppModel,
        layoutEngine: LayoutEngine,
        registry: WidgetRegistry,
        history: MetricsHistory,
        pluginManager: PluginManager
    ) {
        let dashboardWindow: NSWindow
        if let existing = window {
            dashboardWindow = existing
        } else {
            let hosting = NSHostingController(
                rootView: AnyView(
                    DashboardShell()
                        .environmentObject(model)
                        .environmentObject(layoutEngine)
                        .environmentObject(registry)
                        .environmentObject(history)
                )
            )
            let created = KioskWindow(contentViewController: hosting)
            created.title = "EdgeControl"
            created.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            created.isReleasedWhenClosed = false
            created.setContentSize(NSSize(width: 1440, height: 405))
            window = created
            dashboardWindow = created
        }

        if let hosting = dashboardWindow.contentViewController as? NSHostingController<AnyView> {
            hosting.rootView = AnyView(
                DashboardShell()
                    .environmentObject(model)
                    .environmentObject(layoutEngine)
                    .environmentObject(registry)
                    .environmentObject(history)
            )
        }

        WindowPlacement.configure(
            dashboardWindow,
            display: model.selectedDisplay,
            kioskMode: layoutEngine.document.globalSettings.kioskMode
        )

        dashboardWindow.orderFrontRegardless()
        dashboardWindow.makeKeyAndOrderFront(nil)
    }
}

@MainActor
final class EdgeControlAppDelegate: NSObject, NSApplicationDelegate {
    private let model: AppModel
    private let layoutEngine: LayoutEngine
    private let registry: WidgetRegistry
    private let history: MetricsHistory
    private let pluginManager: PluginManager
    private let dashboardWindowController = DashboardWindowController()

    init(model: AppModel, layoutEngine: LayoutEngine, registry: WidgetRegistry, history: MetricsHistory, pluginManager: PluginManager) {
        self.model = model
        self.layoutEngine = layoutEngine
        self.registry = registry
        self.history = history
        self.pluginManager = pluginManager
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.mainMenu = buildMainMenu()
        // Pre-configure SettingsWindowController with all dependencies
        SettingsWindowController.shared.configure(
            model: model,
            layoutEngine: layoutEngine,
            registry: registry,
            pluginManager: pluginManager
        )
        dashboardWindowController.show(
            model: model,
            layoutEngine: layoutEngine,
            registry: registry,
            history: history,
            pluginManager: pluginManager
        )
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationWillTerminate(_ notification: Notification) {
        model.widgetDataBridge?.flush()
        model.stop()
        // Flush any pending debounced layout save
        layoutEngine.flushSave()
    }

    @objc private func quitApp(_ sender: Any?) {
        NSApp.terminate(nil)
    }

    private func buildMainMenu() -> NSMenu {
        let mainMenu = NSMenu()
        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        let quitItem = NSMenuItem(title: "Quit EdgeControl", action: #selector(quitApp(_:)), keyEquivalent: "q")
        quitItem.keyEquivalentModifierMask = [.command]
        appMenu.addItem(quitItem)
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)
        return mainMenu
    }
}

@main
enum EdgeControlExecutable {
    static func main() {
        signal(SIGPIPE, SIG_IGN)

        let store = LayoutStore()
        let layoutEngine = LayoutEngine(store: store)

        // Single source of truth: GlobalSettings in layout.json
        let model = AppModel(selectedDisplayName: layoutEngine.document.globalSettings.selectedDisplayName)
        model.startIfNeeded()

        let pluginManager = PluginManager()
        pluginManager.discoverAndLoad()

        let history = MetricsHistory()

        let registry = WidgetRegistry()
        registry.registerNativeWidgets(model: model, history: history)
        registry.registerPluginWidgets(pluginManager: pluginManager)

        // Activate only services needed by widgets currently in the layout
        let neededServices = registry.requiredServices(for: layoutEngine.document)
        model.updateActiveServices(neededServices: neededServices)

        // Bridge: write metrics to shared container for desktop widgets
        let widgetBridge = WidgetDataBridge(model: model)
        widgetBridge.start()
        model.widgetDataBridge = widgetBridge

        // Plugin desktop widget renderer: headless WKWebView snapshots
        let pluginRenderer = PluginWidgetRenderer(pluginManager: pluginManager, model: model)
        pluginRenderer.start()
        model.pluginWidgetRenderer = pluginRenderer

        let app = NSApplication.shared
        let delegate = EdgeControlAppDelegate(
            model: model,
            layoutEngine: layoutEngine,
            registry: registry,
            history: history,
            pluginManager: pluginManager
        )
        app.delegate = delegate
        withExtendedLifetime(delegate) {
            app.run()
        }
    }
}
