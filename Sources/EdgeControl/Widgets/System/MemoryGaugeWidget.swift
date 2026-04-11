import SwiftUI

public final class MemoryGaugeWidget: DashboardWidget {
    public let widgetId = "memory-gauge"
    public let displayName = "Memory Gauge"
    public let description = "Radial gauge showing memory usage with used/total GB"
    public let iconName = "memorychip"
    public let category: WidgetCategory = .system
    public let requiredServices: Set<ServiceKey> = [.metrics]
    public let supportedSizes = WidgetSizeRange(min: .size(2, 2), max: .size(6, 4))
    public let defaultSize = WidgetSize.size(4, 3)

    public let configSchema: [ConfigSchemaEntry] = [
        ConfigSchemaEntry(key: "showUsedGB", label: "Show Used GB", type: .toggle, defaultValue: .bool(true)),
        ConfigSchemaEntry(key: "showLabel", label: "Show Label", type: .toggle, defaultValue: .bool(true)),
    ]
    public let defaultColors = WidgetColors(primary: .purple)

    private let metricsService: SystemMetricsService

    public init(metricsService: SystemMetricsService) {
        self.metricsService = metricsService
    }

    @MainActor
    public func body(size: WidgetSize, config: WidgetConfig) -> any View {
        MemoryGaugeWidgetView(
            metricsService: metricsService,
            showUsedGB: config.bool("showUsedGB", default: true),
            showLabel: config.bool("showLabel", default: true),
            isCompact: size.width <= 2 && size.height <= 2
        )
    }
}

private struct MemoryGaugeWidgetView: View {
    @ObservedObject var metricsService: SystemMetricsService
    @Environment(\.themeSettings) private var ts
    let showUsedGB: Bool
    let showLabel: Bool
    let isCompact: Bool

    var body: some View {
        let mem = metricsService.latest
        let percent = mem?.memoryUsedPercent ?? 0
        let usedGB = mem?.memoryUsedGB ?? 0
        let totalGB = mem?.memoryTotalGB ?? 0

        let unitText: String = {
            if isCompact { return "" }
            if showUsedGB { return String(format: "%.1f / %.0f GB", usedGB, totalGB) }
            return ""
        }()

        RadialGaugeView(
            value: percent,
            maxValue: 100,
            label: "MEMORY",
            displayValue: String(format: "%.0f%%", percent),
            unit: unitText,
            accentColor: Theme.widgetPrimary("memory-gauge", ts: ts, default: .purple),
            showLabel: showLabel && !isCompact
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(Theme.compactPadding)
        .widgetCard()
    }
}
