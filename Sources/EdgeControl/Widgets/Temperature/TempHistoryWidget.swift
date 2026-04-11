import SwiftUI

public final class TempHistoryWidget: DashboardWidget {
    public let widgetId = "temp-history"
    public let displayName = "Temperature History"
    public let description = "Multi-sensor temperature history graph (CPU, GPU, SSD)"
    public let iconName = "chart.line.uptrend.xyaxis"
    public let category: WidgetCategory = .temperature
    public let requiredServices: Set<ServiceKey> = [.smc]
    public let supportedSizes = WidgetSizeRange(min: .size(4, 2), max: .size(10, 4))
    public let defaultSize = WidgetSize.size(6, 3)

    public let configSchema: [ConfigSchemaEntry] = []
    public let defaultColors = WidgetColors(primary: .cyan, secondary: .orange)

    private let service: SMCService

    public init(service: SMCService) {
        self.service = service
    }

    @MainActor
    public func body(size: WidgetSize, config: WidgetConfig) -> any View {
        TempHistoryWidgetView(service: service, isCompact: size.height <= 2)
    }
}

private struct TempHistoryWidgetView: View {
    @ObservedObject var service: SMCService
    @Environment(\.themeSettings) private var ts
    let isCompact: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: isCompact ? 2 : 8) {
            if !isCompact {
                HStack {
                    Text("TEMPERATURE")
                        .font(Theme.title(ts))
                        .foregroundStyle(Theme.text3(ts))
                    Spacer()

                    if let cpu = service.cpuTemperature {
                        legendChip("CPU", value: String(format: "%.0f°", cpu), color: Theme.widgetPrimary("temp-history", ts: ts, default: .cyan))
                    }
                    if let gpu = service.gpuTemperature {
                        legendChip("GPU", value: String(format: "%.0f°", gpu), color: Theme.widgetSecondary("temp-history", ts: ts, default: .orange) ?? Theme.accentOrange)
                    }
                }
            }

            GeometryReader { geo in
                ZStack {
                    if !service.cpuTempHistory.isEmpty {
                        HistoryGraphView(
                            history: service.cpuTempHistory.map { $0 / 110 },
                            color: Theme.widgetPrimary("temp-history", ts: ts, default: .cyan),
                            showAxisLabels: false,
                            showCurrentDot: !isCompact
                        )
                    }
                    if !service.gpuTempHistory.isEmpty {
                        HistoryGraphView(
                            history: service.gpuTempHistory.map { $0 / 110 },
                            color: Theme.widgetSecondary("temp-history", ts: ts, default: .orange) ?? Theme.accentOrange,
                            showAxisLabels: false,
                            showCurrentDot: !isCompact
                        )
                    }
                }
            }
        }
        .padding(isCompact ? Theme.compactPadding : Theme.sectionSpacing)
        .widgetCard()
    }

    private func legendChip(_ label: String, value: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(label)
                .font(Theme.caption(ts))
                .foregroundStyle(Theme.text3(ts))
            Text(value)
                .font(Theme.label(ts))
                .foregroundStyle(color)
                .monospacedDigit()
        }
    }
}
