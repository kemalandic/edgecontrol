import SwiftUI

public final class NetworkStatsWidget: DashboardWidget {
    public let widgetId = "network-stats"
    public let displayName = "Network Stats"
    public let description = "Real-time download/upload speeds and total transferred data"
    public let iconName = "network"
    public let category: WidgetCategory = .network
    public let requiredServices: Set<ServiceKey> = [.network]
    public let supportedSizes = WidgetSizeRange(min: .size(3, 2), max: .size(8, 4))
    public let defaultSize = WidgetSize.size(4, 3)

    public let configSchema: [ConfigSchemaEntry] = []
    public let defaultColors = WidgetColors(primary: .green, secondary: .cyan)

    private let service: NetworkMonitorService

    public init(service: NetworkMonitorService) {
        self.service = service
    }

    @MainActor
    public func body(size: WidgetSize, config: WidgetConfig) -> any View {
        NetworkStatsWidgetView(service: service, isCompact: size.height <= 2)
    }
}

private struct NetworkStatsWidgetView: View {
    @ObservedObject var service: NetworkMonitorService
    @Environment(\.themeSettings) private var ts
    let isCompact: Bool

    var body: some View {
        let primary = Theme.widgetPrimary("network-stats", ts: ts, default: .green)
        let secondary = Theme.widgetSecondary("network-stats", ts: ts, default: .cyan) ?? Theme.accentCyan

        VStack(spacing: isCompact ? 6 : 12) {
            if !isCompact {
                WidgetHeader(title: "NETWORK", color: primary)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.system(size: (isCompact ? 14 : 20) * ts.fontScale))
                        .foregroundStyle(primary)
                    Text("DOWN")
                        .font(Theme.label(ts))
                        .foregroundStyle(Theme.text3(ts))
                    Spacer()
                    Text(NetworkMonitorService.formatSpeed(service.downloadSpeed))
                        .font(Theme.value(ts))
                        .foregroundStyle(Theme.text1(ts))
                        .monospacedDigit()
                        .minimumScaleFactor(0.5)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: (isCompact ? 14 : 20) * ts.fontScale))
                        .foregroundStyle(secondary)
                    Text("UP")
                        .font(Theme.label(ts))
                        .foregroundStyle(Theme.text3(ts))
                    Spacer()
                    Text(NetworkMonitorService.formatSpeed(service.uploadSpeed))
                        .font(Theme.value(ts))
                        .foregroundStyle(Theme.text1(ts))
                        .monospacedDigit()
                        .minimumScaleFactor(0.5)
                }
            }

            if !isCompact {
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
