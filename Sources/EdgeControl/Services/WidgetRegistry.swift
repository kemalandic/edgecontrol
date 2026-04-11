import SwiftUI

/// Central registry for all available widgets (native + plugin).
/// Settings UI reads from here to show the widget catalog.
/// GridPageView uses this to instantiate widgets by ID.
@MainActor
public final class WidgetRegistry: ObservableObject {
    @Published public private(set) var widgets: [String: any DashboardWidget] = [:]

    public init() {}

    // MARK: - Registration

    public func register(_ widget: any DashboardWidget) {
        widgets[widget.widgetId] = widget
    }

    public func unregister(widgetId: String) {
        widgets.removeValue(forKey: widgetId)
    }

    // MARK: - Lookup

    public func widget(for id: String) -> (any DashboardWidget)? {
        widgets[id]
    }

    // MARK: - Catalog Queries

    public var allWidgets: [any DashboardWidget] {
        Array(widgets.values).sorted { $0.displayName < $1.displayName }
    }

    public func widgets(in category: WidgetCategory) -> [any DashboardWidget] {
        allWidgets.filter { $0.category == category }
    }

    public var categories: [WidgetCategory] {
        let present = Set(widgets.values.map(\.category))
        return WidgetCategory.allCases.filter { present.contains($0) }
    }

    /// Collect all required services for widgets currently placed in the layout.
    public func requiredServices(for document: LayoutDocument) -> Set<ServiceKey> {
        var services = Set<ServiceKey>()
        for page in document.pages {
            for placement in page.widgets {
                if let widget = widgets[placement.widgetId] {
                    services.formUnion(widget.requiredServices)
                }
            }
        }
        return services
    }

    /// Returns widget metadata without needing the full widget instance.
    public func metadata(for widgetId: String) -> WidgetMetadata? {
        guard let w = widgets[widgetId] else { return nil }
        return WidgetMetadata(
            widgetId: w.widgetId,
            displayName: w.displayName,
            description: w.description,
            iconName: w.iconName,
            category: w.category,
            supportedSizes: w.supportedSizes,
            defaultSize: w.defaultSize,
            isConfigurable: w.isConfigurable
        )
    }

    // MARK: - Register All Native Widgets

    public func registerNativeWidgets(model: AppModel, history: MetricsHistory) {
        // System
        register(CPUGaugeWidget(metricsService: model.metricsService))
        register(MemoryGaugeWidget(metricsService: model.metricsService))
        register(CPUHistoryWidget(metricsService: model.metricsService, history: history))
        register(MemoryHistoryWidget(metricsService: model.metricsService, history: history))
        register(ProcessListWidget(service: model.processService))
        register(DiskIOWidget(service: model.diskIOService))
        register(StorageBarsWidget(metricsService: model.metricsService))
        register(MemoryPressureWidget(metricsService: model.metricsService))
        register(CPUCoresWidget(metricsService: model.metricsService))

        // Temperature
        register(CPUTempWidget(service: model.smcService))
        register(GPUTempWidget(service: model.smcService))
        register(TempHistoryWidget(service: model.smcService))
        register(SSDTempWidget(service: model.smcService))
        register(PerCoreTempWidget(service: model.smcService))

        // Network
        register(NetworkStatsWidget(service: model.networkService))
        register(WiFiInfoWidget(service: model.wifiService))
        register(BluetoothWidget(service: model.bluetoothService))

        // Media
        register(NowPlayingWidget(service: model.nowPlayingService))
        register(AudioDevicesWidget(service: model.audioService))

        // Info
        register(WeatherWidget(service: model.weatherService))
        register(ClockWidget())
        register(WorldClocksWidget())
        register(DayProgressWidget())
        register(MoonPhaseWidget())

        // DevTools
        register(CICDRunsWidget(service: model.githubService))
    }

    /// Register all widgets from enabled plugins.
    public func registerPluginWidgets(pluginManager: PluginManager) {
        // Remove previously registered plugin widgets
        let pluginIds = widgets.keys.filter { $0.contains(".") && widgets[$0]?.category == .plugin }
        for id in pluginIds { widgets.removeValue(forKey: id) }

        // Register from enabled plugins
        for (plugin, widgetDef) in pluginManager.allWidgetDefs() {
            let pluginWidget = PluginWebWidget(
                pluginId: plugin.manifest.id,
                widgetDef: widgetDef,
                permissions: plugin.manifest.permissions,
                bundlePath: plugin.bundlePath,
                allowedDomains: plugin.manifest.allowedDomains
            )
            register(pluginWidget)
        }
    }
}

// MARK: - Widget Metadata (lightweight, for catalog display)

public struct WidgetMetadata: Identifiable, Sendable {
    public let widgetId: String
    public let displayName: String
    public let description: String
    public let iconName: String
    public let category: WidgetCategory
    public let supportedSizes: WidgetSizeRange
    public let defaultSize: WidgetSize
    public let isConfigurable: Bool

    public var id: String { widgetId }
}
