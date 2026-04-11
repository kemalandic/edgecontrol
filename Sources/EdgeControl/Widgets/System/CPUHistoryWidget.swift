import SwiftUI

public final class CPUHistoryWidget: DashboardWidget {
    public let widgetId = "cpu-history"
    public let displayName = "CPU History"
    public let description = "Time-series graph of CPU usage over the last few minutes"
    public let iconName = "chart.xyaxis.line"
    public let category: WidgetCategory = .system
    public let requiredServices: Set<ServiceKey> = [.metrics]
    public let supportedSizes = WidgetSizeRange(min: .size(3, 2), max: .size(10, 4))
    public let defaultSize = WidgetSize.size(6, 3)

    public let configSchema: [ConfigSchemaEntry] = []
    public let defaultColors = WidgetColors(primary: .cyan)

    private let metricsService: SystemMetricsService
    private let history: MetricsHistory

    public init(metricsService: SystemMetricsService, history: MetricsHistory) {
        self.metricsService = metricsService
        self.history = history
    }

    @MainActor
    public func body(size: WidgetSize, config: WidgetConfig) -> any View {
        CPUHistoryWidgetView(
            metricsService: metricsService,
            history: history,
            isCompact: size.height <= 2
        )
    }
}

private struct CPUHistoryWidgetView: View {
    @ObservedObject var metricsService: SystemMetricsService
    @ObservedObject var history: MetricsHistory
    @Environment(\.themeSettings) private var ts
    let isCompact: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: isCompact ? 2 : 6) {
            HStack {
                Text("CPU USAGE")
                    .font(isCompact ? Theme.font(size: ts.fontSizeCaption * 1.5, weight: .heavy, settings: ts) : Theme.title(ts))
                    .foregroundStyle(Theme.text3(ts))
                Spacer()
                Text(String(format: "%.1f%%", metricsService.latest?.cpuLoadPercent ?? 0))
                    .font(isCompact ? Theme.font(size: ts.fontSizeLabel * 1.5, weight: .heavy, settings: ts) : Theme.value(ts))
                    .foregroundStyle(Theme.widgetPrimary("cpu-history", ts: ts, default: .cyan))
                    .monospacedDigit()
            }

            HistoryGraphView(
                history: history.cpuHistory,
                color: Theme.widgetPrimary("cpu-history", ts: ts, default: .cyan),
                showAxisLabels: !isCompact
            )
            .frame(maxHeight: .infinity)
        }
        .padding(isCompact ? Theme.compactPadding : Theme.sectionSpacing)
        .widgetCard()
    }
}
