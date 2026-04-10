import SwiftUI

public final class CPUCoresWidget: DashboardWidget {
    public let widgetId = "cpu-cores"
    public let displayName = "CPU Cores"
    public let description = "Individual CPU core usage with per-core load bars"
    public let iconName = "cpu"
    public let category: WidgetCategory = .system
    public let supportedSizes = WidgetSizeRange(min: .size(4, 3), max: .size(10, 6))
    public let defaultSize = WidgetSize.size(8, 6)

    public let configSchema: [ConfigSchemaEntry] = []
    public let defaultColors = WidgetColors(primary: .purple)

    private let metricsService: SystemMetricsService

    public init(metricsService: SystemMetricsService) {
        self.metricsService = metricsService
    }

    @MainActor
    public func body(size: WidgetSize, config: WidgetConfig) -> any View {
        CPUCoresWidgetView(metricsService: metricsService, columns: size.width >= 8 ? 2 : 1)
    }
}

private struct CPUCoresWidgetView: View {
    @ObservedObject var metricsService: SystemMetricsService
    @Environment(\.themeSettings) private var ts
    let columns: Int

    private var primary: Color { Theme.widgetPrimary("cpu-cores", ts: ts, default: .purple) }

    private func usageColor(_ usage: Double) -> Color {
        if usage < 30 { return Theme.accentCyan }
        if usage < 60 { return Theme.accentGreen }
        if usage < 80 { return Theme.accentYellow }
        return Theme.accentRed
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                WidgetHeader(title: "CPU USAGE", color: primary)
                Spacer()
                Text("\(metricsService.perCoreUsage.count) CORES")
                    .font(Theme.caption(ts))
                    .foregroundStyle(Theme.text3(ts))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            // Core list
            ScrollView(.vertical, showsIndicators: false) {
                if columns == 2 {
                    let cores = metricsService.perCoreUsage
                    let half = (cores.count + 1) / 2
                    let left = Array(cores.prefix(half))
                    let right = Array(cores.suffix(from: min(half, cores.count)))

                    HStack(alignment: .top, spacing: 4) {
                        VStack(spacing: 2) {
                            ForEach(left) { core in
                                coreRow(core)
                            }
                        }
                        VStack(spacing: 2) {
                            ForEach(right) { core in
                                coreRow(core)
                            }
                        }
                    }
                    .padding(.horizontal, 8)
                } else {
                    VStack(spacing: 2) {
                        ForEach(metricsService.perCoreUsage) { core in
                            coreRow(core)
                        }
                    }
                    .padding(.horizontal, 8)
                }
            }
        }
        .widgetCard()
    }

    private func coreRow(_ core: CoreUsage) -> some View {
        let color = usageColor(core.usage)

        return HStack(spacing: 6) {
            Text("C\(core.id)")
                .font(.system(size: 11 * ts.fontScale, weight: .bold, design: .monospaced))
                .foregroundStyle(primary)
                .frame(width: 28, alignment: .leading)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.white.opacity(0.06))
                    RoundedRectangle(cornerRadius: 3)
                        .fill(color)
                        .frame(width: geo.size.width * min(core.usage / 100, 1))
                }
            }
            .frame(height: 12)

            Text(String(format: "%.0f%%", core.usage))
                .font(.system(size: 11 * ts.fontScale, weight: .bold, design: .monospaced))
                .foregroundStyle(color)
                .frame(width: 32, alignment: .trailing)
        }
        .frame(height: 18)
    }
}
