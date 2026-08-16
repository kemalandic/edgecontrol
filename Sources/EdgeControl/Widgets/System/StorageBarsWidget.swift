import SwiftUI

public final class StorageBarsWidget: DashboardWidget {
    public let widgetId = "storage-bars"
    public let displayName = "Storage"
    public let description = "Disk usage with circular gauge showing used/free/total"
    public let iconName = "externaldrive"
    public let category: WidgetCategory = .system
    public let requiredServices: Set<ServiceKey> = [.metrics]
    public let supportedSizes = WidgetSizeRange(min: .size(2, 1), max: .size(8, 4))
    public let defaultSize = WidgetSize.size(4, 3)

    public let configSchema: [ConfigSchemaEntry] = []
    public let defaultColors = WidgetColors(primary: .blue, secondary: .purple, tertiary: .green)

    private let metricsService: SystemMetricsService

    public init(metricsService: SystemMetricsService) {
        self.metricsService = metricsService
    }

    @MainActor
    public func body(size: WidgetSize, config: WidgetConfig) -> any View {
        // Full ring needs 3 rows, or 2 rows when at least 4 columns wide;
        // smaller cells fall back to the bar-only layout.
        StorageBarsWidgetView(
            metricsService: metricsService,
            isCompact: size.height == 1 || (size.height == 2 && size.width <= 3),
            isBar: size.height == 1
        )
    }
}

private struct StorageBarsWidgetView: View {
    @ObservedObject var metricsService: SystemMetricsService
    @Environment(\.themeSettings) private var ts
    let isCompact: Bool
    let isBar: Bool

    var body: some View {
        let m = metricsService.latest
        let primary = Theme.widgetPrimary("storage-bars", ts: ts, default: .blue)
        let secondary = Theme.widgetSecondary("storage-bars", ts: ts, default: .purple) ?? Theme.accentPurple
        let tertiary = Theme.widgetTertiary("storage-bars", ts: ts, default: .green) ?? Theme.accentGreen

        VStack(spacing: isCompact ? 6 : 12) {
            if !isCompact {
                WidgetHeader(title: "STORAGE", color: primary)
            }

            if let m {
                if isCompact {
                    if !isBar { Spacer(minLength: 0) }
                    VStack(spacing: 4) {
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 4).fill(Color.white.opacity(0.08))
                                RoundedRectangle(cornerRadius: 4).fill(primary)
                                    .frame(width: geo.size.width * m.storageUsedPercent / 100)
                            }
                        }
                        .frame(height: 8)
                        HStack {
                            Text(String(format: "%.0f%%", m.storageUsedPercent))
                                .font(Theme.title(ts))
                                .foregroundStyle(Theme.text1(ts))
                            Spacer()
                            Text(String(format: "%.0f / %.0f GB", m.storageUsedGB, m.storageTotalGB))
                                .font(Theme.label(ts))
                                .foregroundStyle(Theme.text2(ts))
                        }
                    }
                    Spacer(minLength: 0)
                } else {
                    GeometryReader { geo in
                        // Ring fills the cell height, leaving ~45% of the width for labels.
                        let side = min(geo.size.height, geo.size.width * 0.55)
                        let ringWidth = min(max(12, side * 0.1), 22)
                        HStack(spacing: 16) {
                            ZStack {
                                Circle()
                                    .trim(from: 0, to: 1)
                                    .stroke(Color.white.opacity(0.08), style: StrokeStyle(lineWidth: ringWidth, lineCap: .round))
                                    .rotationEffect(.degrees(-90))
                                Circle()
                                    .trim(from: 0, to: m.storageUsedPercent / 100)
                                    .stroke(
                                        AngularGradient(colors: [primary, secondary], center: .center),
                                        style: StrokeStyle(lineWidth: ringWidth, lineCap: .round)
                                    )
                                    .rotationEffect(.degrees(-90))
                                VStack(spacing: 2) {
                                    Text(String(format: "%.0f%%", m.storageUsedPercent))
                                        .font(Theme.value(ts))
                                        .foregroundStyle(Theme.text1(ts))
                                    Text("USED")
                                        .font(Theme.caption(ts))
                                        .foregroundStyle(Theme.text2(ts))
                                }
                            }
                            // Stroke centers on the path; inset so it stays inside the frame.
                            .padding(ringWidth / 2)
                            .frame(width: side, height: side)

                            VStack(alignment: .leading, spacing: 8) {
                                storageLabel("USED", value: String(format: "%.0f GB", m.storageUsedGB), color: primary)
                                storageLabel("FREE", value: String(format: "%.0f GB", m.storageTotalGB - m.storageUsedGB), color: tertiary)
                                storageLabel("TOTAL", value: String(format: "%.0f GB", m.storageTotalGB), color: Theme.text2(ts))
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            } else {
                Spacer(minLength: 0)
            }
        }
        .padding(isCompact ? Theme.compactPadding : Theme.widgetPadding)
        .widgetCard()
    }

    private func storageLabel(_ label: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(Theme.title(ts))
                .foregroundStyle(color)
            Text(label)
                .font(Theme.caption(ts))
                .foregroundStyle(Theme.text2(ts))
        }
    }
}
