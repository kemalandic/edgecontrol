import SwiftUI

public final class NetworkStatsWidget: DashboardWidget {
    public let widgetId = "network-stats"
    public let displayName = "Network Stats"
    public let description = "Real-time download/upload speeds and total transferred data"
    public let iconName = "network"
    public let category: WidgetCategory = .network
    public let requiredServices: Set<ServiceKey> = [.network]
    public let supportedSizes = WidgetSizeRange(min: .size(1, 1), max: .size(8, 4))
    public let defaultSize = WidgetSize.size(4, 3)

    public let configSchema: [ConfigSchemaEntry] = []
    public let defaultColors = WidgetColors(primary: .green, secondary: .cyan)

    private let service: NetworkMonitorService

    public init(service: NetworkMonitorService) {
        self.service = service
    }

    @MainActor
    public func body(size: WidgetSize, config: WidgetConfig) -> any View {
        NetworkStatsWidgetView(
            service: service,
            isCompact: size.height <= 2,
            isBar: size.height <= 1,
            isNarrow: size.width <= 1,
            showTitle: true,
            showCompactTotals: size.width >= 5 && size.height >= 2
        )
    }
}

private struct NetworkStatsWidgetView: View {
    @ObservedObject var service: NetworkMonitorService
    @Environment(\.themeSettings) private var ts
    let isCompact: Bool
    // Single grid row: the stacked DOWN/UP rows would overflow ~112px of
    // interior height at larger font scales, so render them side by side.
    let isBar: Bool
    // One grid column: stacked groups under a slim caption.
    let isNarrow: Bool
    // Keep the widget's name visible wherever it fits — full header down to
    // 2 rows, a bare caption in the 1-row layout — matching Disk I/O.
    let showTitle: Bool
    // Wide-and-tall compact (width >= 5, height >= 2) has room for the
    // DL/UL totals row; the 1-row bar layout never does.
    let showCompactTotals: Bool

    var body: some View {
        let primary = Theme.widgetPrimary("network-stats", ts: ts, default: .green)
        let secondary = Theme.widgetSecondary("network-stats", ts: ts, default: .cyan) ?? Theme.accentCyan

        VStack(spacing: isCompact ? 6 : 12) {
            if (!isCompact || (showTitle && !isBar)) && !isNarrow {
                WidgetHeader(title: "NETWORK", color: primary)
            } else if showTitle {
                Text("NETWORK")
                    .font(Theme.caption(ts))
                    .foregroundStyle(Theme.text3(ts))
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Spacer(minLength: 0)

            // Same component Disk I/O renders — equal boxes, equal layout.
            RatePairView(
                first: .init(
                    icon: "arrow.down.circle.fill", label: "DOWN",
                    value: NetworkMonitorService.formatSpeed(service.downloadSpeed),
                    color: primary
                ),
                second: .init(
                    icon: "arrow.up.circle.fill", label: "UP",
                    value: NetworkMonitorService.formatSpeed(service.uploadSpeed),
                    color: secondary
                ),
                compact: isCompact,
                vertical: isNarrow
            )

            if !isBar && (!isCompact || showCompactTotals) {
                HStack(spacing: 10) {
                    totalChip("DL", value: NetworkMonitorService.formatBytes(service.totalDownloaded), color: primary)
                    totalChip("UL", value: NetworkMonitorService.formatBytes(service.totalUploaded), color: secondary)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(isCompact ? Theme.compactPadding : Theme.widgetPadding)
        .widgetCard()
    }



    private func totalChip(_ label: String, value: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .font(Theme.caption(ts))
                .foregroundStyle(Theme.text3(ts))
            Text(value)
                .font(Theme.body(ts))
                .foregroundStyle(Theme.text1(ts))
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity)
        .padding(Theme.itemSpacing)
        .background(Color.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
