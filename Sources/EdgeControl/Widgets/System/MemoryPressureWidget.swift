import SwiftUI

public final class MemoryPressureWidget: DashboardWidget {
    public let widgetId = "memory-pressure"
    public let displayName = "Memory Pressure"
    public let description = "Memory pressure gauge with swap usage indicator"
    public let iconName = "gauge.with.dots.needle.33percent"
    public let category: WidgetCategory = .system
    public let supportedSizes = WidgetSizeRange(min: .size(2, 2), max: .size(6, 4))
    public let defaultSize = WidgetSize.size(4, 3)

    public let configSchema: [ConfigSchemaEntry] = [
        ConfigSchemaEntry(key: "showSwap", label: "Show Swap", type: .toggle, defaultValue: .bool(true)),
        ConfigSchemaEntry(key: "showLabel", label: "Show Label", type: .toggle, defaultValue: .bool(true)),
    ]
    public let defaultColors = WidgetColors(primary: .orange)

    private let metricsService: SystemMetricsService

    public init(metricsService: SystemMetricsService) {
        self.metricsService = metricsService
    }

    @MainActor
    public func body(size: WidgetSize, config: WidgetConfig) -> any View {
        MemoryPressureWidgetView(
            metricsService: metricsService,
            showSwap: config.bool("showSwap", default: true),
            showLabel: config.bool("showLabel", default: true),
            isCompact: size.width <= 2 && size.height <= 2
        )
    }
}

private struct MemoryPressureWidgetView: View {
    @ObservedObject var metricsService: SystemMetricsService
    @Environment(\.themeSettings) private var ts
    let showSwap: Bool
    let showLabel: Bool
    let isCompact: Bool

    var body: some View {
        let m = metricsService.latest
        let pressure = m?.memoryPressurePercent ?? 0
        let swap = m?.swapUsedMB ?? 0
        let primary = Theme.widgetPrimary("memory-pressure", ts: ts, default: .orange)

        let swapText: String = {
            if !showSwap || isCompact { return "" }
            if swap < 1 { return "SWAP 0MB" }
            if swap < 1024 { return String(format: "SWAP %.0fMB", swap) }
            return String(format: "SWAP %.1fGB", swap / 1024)
        }()

        RadialGaugeView(
            value: pressure,
            maxValue: 100,
            label: "PRESSURE",
            displayValue: String(format: "%.0f%%", pressure),
            unit: swapText,
            accentColor: primary,
            showLabel: showLabel && !isCompact
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(Theme.compactPadding)
        .widgetCard()
    }
}
