import SwiftUI

public final class PerCoreTempWidget: DashboardWidget {
    public let widgetId = "per-core-temp"
    public let displayName = "Per-Core Temp"
    public let description = "Individual CPU core temperatures with P/E core distinction"
    public let iconName = "cpu"
    public let category: WidgetCategory = .temperature
    public let supportedSizes = WidgetSizeRange(min: .size(4, 3), max: .size(10, 6))
    public let defaultSize = WidgetSize.size(8, 6)

    public let configSchema: [ConfigSchemaEntry] = []
    public let defaultColors = WidgetColors(primary: .cyan, secondary: .green)

    private let service: SMCService

    public init(service: SMCService) {
        self.service = service
    }

    @MainActor
    public func body(size: WidgetSize, config: WidgetConfig) -> any View {
        PerCoreTempWidgetView(service: service, columns: size.width >= 8 ? 2 : 1)
    }
}

private struct PerCoreTempWidgetView: View {
    @ObservedObject var service: SMCService
    @Environment(\.themeSettings) private var ts
    let columns: Int

    private var primary: Color { Theme.widgetPrimary("per-core-temp", ts: ts, default: .cyan) }
    private var secondary: Color { Theme.widgetSecondary("per-core-temp", ts: ts, default: .green) ?? Theme.accentGreen }

    private func tempColor(_ temp: Double) -> Color {
        if temp < 55 { return Theme.accentGreen }
        if temp < 70 { return Theme.accentYellow }
        if temp < 80 { return Theme.accentOrange }
        return Theme.accentRed
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                WidgetHeader(title: "PER-CORE", color: primary)
                Spacer()
                Text("\(service.cpuCoreTemps.count) CORES")
                    .font(Theme.caption(ts))
                    .foregroundStyle(Theme.text3(ts))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            // Core list
            ScrollView(.vertical, showsIndicators: false) {
                if columns == 2 {
                    let cores = service.cpuCoreTemps
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
                        ForEach(service.cpuCoreTemps) { core in
                            coreRow(core)
                        }
                    }
                    .padding(.horizontal, 8)
                }
            }
        }
        .widgetCard()
    }

    private func coreRow(_ core: CoreTemp) -> some View {
        let color = tempColor(core.temperature)
        let maxTemp: Double = 105

        return HStack(spacing: 6) {
            Text(core.label)
                .font(.system(size: 11 * ts.fontScale, weight: .bold, design: .monospaced))
                .foregroundStyle(core.isPerformance ? primary : secondary)
                .frame(width: 28, alignment: .leading)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.white.opacity(0.06))
                    RoundedRectangle(cornerRadius: 3)
                        .fill(color)
                        .frame(width: geo.size.width * min(core.temperature / maxTemp, 1))
                }
            }
            .frame(height: 12)

            Text(String(format: "%.0f°", core.temperature))
                .font(.system(size: 11 * ts.fontScale, weight: .bold, design: .monospaced))
                .foregroundStyle(color)
                .frame(width: 32, alignment: .trailing)
        }
        .frame(height: 18)
    }
}
