import SwiftUI
import WidgetKit

struct SystemGaugeWidget: Widget {
    let kind = "SystemGauge"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: SystemGaugeProvider()) { entry in
            SystemGaugeWidgetView(entry: entry)
                .containerBackground(WidgetColors.background, for: .widget)
        }
        .configurationDisplayName("System Monitor")
        .description("CPU and memory usage gauges")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct SystemGaugeWidgetView: View {
    let entry: SystemGaugeEntry

    @Environment(\.widgetFamily) var family

    var body: some View {
        Group {
            switch family {
            case .systemSmall:
                smallView
            case .systemMedium:
                mediumView
            default:
                smallView
            }
        }
        .staleOverlay(isStale: entry.isStale, minutesAgo: entry.minutesAgo)
    }

    private var smallView: some View {
        WidgetGaugeView(
            value: entry.cpuUsage,
            label: "CPU",
            displayValue: WidgetFormatters.percent(entry.cpuUsage),
            accentColor: WidgetColors.gaugeColor(for: entry.cpuUsage)
        )
        .padding(8)
    }

    private var mediumView: some View {
        HStack(spacing: 16) {
            WidgetGaugeView(
                value: entry.cpuUsage,
                label: "CPU",
                displayValue: WidgetFormatters.percent(entry.cpuUsage),
                accentColor: WidgetColors.gaugeColor(for: entry.cpuUsage)
            )

            WidgetGaugeView(
                value: entry.memoryUsage,
                label: "MEMORY",
                displayValue: WidgetFormatters.percent(entry.memoryUsage),
                accentColor: WidgetColors.gaugeColor(for: entry.memoryUsage)
            )

            VStack(alignment: .leading, spacing: 4) {
                Spacer()
                Text(String(format: "%.1f / %.0f GB", entry.memoryUsedGB, entry.memoryTotalGB))
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(WidgetColors.textSecondary)
                Spacer()
            }
        }
        .padding(12)
    }
}
