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
    private var statusItem: NSStatusItem?

    init(model: AppModel, layoutEngine: LayoutEngine, registry: WidgetRegistry, history: MetricsHistory, pluginManager: PluginManager) {
        self.model = model
        self.layoutEngine = layoutEngine
        self.registry = registry
        self.history = history
        self.pluginManager = pluginManager
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Accessory policy: no Dock icon, no Cmd-Tab entry. EdgeControl
        // is a kiosk dashboard living on a secondary display; the
        // menu-bar status item below is the primary user-facing
        // affordance on the main Mac.
        NSApp.setActivationPolicy(.accessory)
        installMenuBarItem()
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

    // MARK: - Menu bar status item

    private func installMenuBarItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            // square.grid.2x2.fill reads instantly as "dashboard" and
            // doesn't clash visually with chart-flavored neighbors in
            // the menu bar. Explicit 16pt + .semibold matches the
            // visual weight of common status items (filled glyphs in
            // a 16pt frame would otherwise render small).
            let config = NSImage.SymbolConfiguration(
                pointSize: 16,
                weight: .semibold
            )
            let image = NSImage(
                systemSymbolName: "square.grid.2x2.fill",
                accessibilityDescription: "EdgeControl"
            )?.withSymbolConfiguration(config)
            image?.isTemplate = true
            button.image = image
        }
        item.menu = buildStatusMenu()
        statusItem = item
    }

    private func buildStatusMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(
            title: "Settings…",
            action: #selector(openSettings(_:)),
            keyEquivalent: ","
        ))
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit EdgeControl", action: #selector(quitApp(_:)), keyEquivalent: "q")
        menu.addItem(quit)
        return menu
    }

    @objc private func openSettings(_ sender: Any?) {
        SettingsWindowController.shared.show()
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
