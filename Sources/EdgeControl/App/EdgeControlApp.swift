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
        let rootView = AnyView(
            DashboardShell()
                .environmentObject(model)
                .environmentObject(layoutEngine)
                .environmentObject(registry)
                .environmentObject(history)
        )

        let dashboardWindow: NSWindow
        if let existing = window {
            dashboardWindow = existing
        } else {
            let created = KioskWindow(
                contentRect: NSRect(x: 0, y: 0, width: 1440, height: 405),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            created.title = "EdgeControl"
            created.isReleasedWhenClosed = false
            created.contentView = KioskHostingView(rootView: rootView)
            window = created
            dashboardWindow = created
        }

        if let hosting = dashboardWindow.contentView as? KioskHostingView<AnyView> {
            hosting.rootView = rootView
        }

        let placed = WindowPlacement.configure(
            dashboardWindow,
            display: model.selectedDisplay,
            kioskMode: layoutEngine.document.globalSettings.kioskMode,
            strictMonitorAffinity: layoutEngine.document.globalSettings.strictMonitorAffinity
        )

        if placed {
            dashboardWindow.orderFrontRegardless()
            dashboardWindow.makeKeyAndOrderFront(nil)
        } else {
            // strictMonitorAffinity is on AND no eligible non-main screen
            // exists — keep the window parked off-screen rather than
            // surfacing it on the main display.
            dashboardWindow.orderOut(nil)
        }
    }

    /// Hide the dashboard window without releasing it — used when the
    /// target display isn't currently enumerated (wake-from-idle race,
    /// monitor unplug, etc.) or before the system is about to sleep /
    /// the session locks. Keeps the window parked off-screen so it
    /// doesn't flash onto the main display while waiting for the
    /// configured target to come back.
    func hide() {
        guard let window else { return }
        window.orderOut(nil)
    }
}

@MainActor
final class EdgeControlAppDelegate: NSObject, NSApplicationDelegate {
    private let model: AppModel
    private let cicdImportPrompt = CICDImportPromptController()
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
        // The menu-bar item is installed either way: in accessory mode it is
        // the only way to reach Settings or quit, and in regular mode it is a
        // convenience next to the normal menu bar.
        Self.sharedMenuBuilder = { [weak self] in self?.buildMainMenu() ?? NSMenu() }
        installMenuBarItem()
        applyActivationPolicy(hideFromDock: layoutEngine.document.globalSettings.hideFromDock)
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
        // One-time offer to import gh/tea logins; no-op once shown or once
        // an account exists.
        cicdImportPrompt.offerIfNeeded(model: model)

        // Re-pin to the configured display whenever the screen topology
        // changes (target display sleep/wake, monitor unplug, dock change),
        // the Mac wakes from idle, or the user session unlocks. Without
        // this the kiosk window migrates to the main display when the
        // target sleeps and never comes back when it wakes.
        let nc = NotificationCenter.default
        nc.addObserver(
            self,
            selector: #selector(repinDashboard),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil,
        )
        let wsNc = NSWorkspace.shared.notificationCenter
        for name in [
            NSWorkspace.didWakeNotification,
            NSWorkspace.screensDidWakeNotification,
            NSWorkspace.sessionDidBecomeActiveNotification,
        ] {
            wsNc.addObserver(
                self,
                selector: #selector(repinDashboard),
                name: name,
                object: nil,
            )
        }

        // Pre-emptively park the window off-screen BEFORE sleep / lock,
        // so when the system wakes macOS can't punt the window to the
        // main display while we wait for the target screen to re-enumerate.
        // The wake-side repin (above) brings it back when ready.
        for name in [
            NSWorkspace.willSleepNotification,
            NSWorkspace.screensDidSleepNotification,
            NSWorkspace.sessionDidResignActiveNotification,
        ] {
            wsNc.addObserver(
                self,
                selector: #selector(parkDashboard),
                name: name,
                object: nil,
            )
        }
    }

    /// On wake / session-active, the target display often isn't yet in
    /// NSScreen.screens — macOS takes a few seconds to re-enumerate after
    /// USB-C / DisplayPort handshakes complete. A single repin call here
    /// would find no target in the screen list and fall back to the main
    /// display. Instead we retry on a short backoff until the target
    /// screen appears or we've burned a reasonable budget.
    @objc private func repinDashboard() {
        retryRepin(attempt: 0)
    }

    /// Hide the window pre-emptively when the screen is about to sleep
    /// or the session resigns active (lock). This prevents macOS from
    /// briefly relocating the window to the main display before our
    /// wake handler fires.
    @objc private func parkDashboard() {
        dashboardWindowController.hide()
    }

    // Backoff schedule: try right away, then doubling out to 60s. Once the
    // target screen appears, the next attempt places + stops retrying.
    private static let repinAttemptDelays: [TimeInterval] = [
        0, 0.5, 1.5, 3, 6, 12, 30, 60, 60, 60,
    ]

    private func retryRepin(attempt: Int) {
        // Hard ceiling at 10 attempts (~ 4 minutes) — beyond that something
        // is wrong with the target display that won't resolve without user
        // action. The window stays hidden meanwhile rather than parking on
        // the wrong display.
        guard attempt < Self.repinAttemptDelays.count else { return }
        let delay = Self.repinAttemptDelays[attempt]
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self else { return }
            let targetName = self.model.selectedDisplay?.name
            let targetPresent = NSScreen.screens.contains { $0.localizedName == targetName }
            if targetPresent || targetName == nil {
                // Target available (or no specific target configured) →
                // place + done.
                self.dashboardWindowController.show(
                    model: self.model,
                    layoutEngine: self.layoutEngine,
                    registry: self.registry,
                    history: self.history,
                    pluginManager: self.pluginManager,
                )
            } else {
                // Target not enumerated yet — hide the window so it doesn't
                // flash onto the main display, and try again later.
                self.dashboardWindowController.hide()
                self.retryRepin(attempt: attempt + 1)
            }
        }
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

    /// Switches between a normal app and a menu-bar-only one.
    ///
    /// Callable at any time, so the Settings toggle takes effect immediately
    /// rather than asking the user to relaunch. `accessory` drops the Dock
    /// icon, the Cmd-Tab entry and the menu bar, which is why the main menu is
    /// only installed in `regular`.
    static func applyActivationPolicy(hideFromDock: Bool, mainMenu: @autoclosure () -> NSMenu) {
        if hideFromDock {
            NSApp.setActivationPolicy(.accessory)
            NSApp.mainMenu = nil
        } else {
            NSApp.setActivationPolicy(.regular)
            NSApp.mainMenu = mainMenu()
        }
    }

    private func applyActivationPolicy(hideFromDock: Bool) {
        Self.applyActivationPolicy(hideFromDock: hideFromDock, mainMenu: buildMainMenu())
    }

    /// Menu used when the app is a normal (non-accessory) app. Static so
    /// Settings can rebuild it when the user turns the Dock back on.
    static func defaultMainMenu() -> NSMenu {
        EdgeControlAppDelegate.sharedMenuBuilder()
    }

    private static var sharedMenuBuilder: () -> NSMenu = { NSMenu() }

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
        let widgetBridge = WidgetDataBridge(model: model, layoutEngine: layoutEngine)
        widgetBridge.start()
        model.widgetDataBridge = widgetBridge

        // Plugin desktop widget renderer: headless WKWebView snapshots.
        // PluginWidgetManifest.write() now runs its disk I/O on a
        // background queue so this call no longer gates start().
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
