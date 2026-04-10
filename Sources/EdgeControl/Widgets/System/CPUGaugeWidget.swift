import SwiftUI

public final class CPUGaugeWidget: DashboardWidget {
    public let widgetId = "cpu-gauge"
    public let displayName = "CPU Gauge"
    public let description = "Radial gauge showing current CPU load percentage"
    public let iconName = "cpu"
    public let category: WidgetCategory = .system
    public let supportedSizes = WidgetSizeRange(min: .size(2, 2), max: .size(6, 4))
    public let defaultSize = WidgetSize.size(4, 3)

    public let configSchema: [ConfigSchemaEntry] = [
        ConfigSchemaEntry(key: "showPercentage", label: "Show Percentage", type: .toggle, defaultValue: .bool(true)),
        ConfigSchemaEntry(key: "showLabel", label: "Show Label", type: .toggle, defaultValue: .bool(true)),
    ]
    public let defaultColors = WidgetColors(primary: .cyan)

    private let metricsService: SystemMetricsService

    public init(metricsService: SystemMetricsService) {
        self.metricsService = metricsService
    }

    @MainActor
    public func body(size: WidgetSize, config: WidgetConfig) -> any View {
        CPUGaugeWidgetView(
            metricsService: metricsService,
            showLabel: config.bool("showLabel", default: true),
            isCompact: size.width <= 2 && size.height <= 2
        )
    }
}

private struct CPUGaugeWidgetView: View {
    @ObservedObject var metricsService: SystemMetricsService
    @Environment(\.themeSettings) private var ts
    let showLabel: Bool
    let isCompact: Bool

    var body: some View {
        let cpu = metricsService.latest?.cpuLoadPercent ?? 0
        let brand = metricsService.latest?.cpuBrand ?? "CPU"

        RadialGaugeView(
            value: cpu,
            maxValue: 100,
            label: "CPU",
            displayValue: String(format: "%.0f%%", cpu),
            unit: isCompact ? "" : abbreviate(brand),
            accentColor: Theme.widgetPrimary("cpu-gauge", ts: ts, default: .cyan),
            showLabel: showLabel && !isCompact
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(Theme.compactPadding)
        .widgetCard()
    }

    private func abbreviate(_ name: String) -> String {
        if name.contains("Apple M") {
            return name.replacingOccurrences(of: "Apple ", with: "")
        }
        if name.count > 20 {
            return String(name.prefix(18)) + "…"
        }
        return name
    }
}
