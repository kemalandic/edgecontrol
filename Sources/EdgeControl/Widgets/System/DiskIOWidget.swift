import SwiftUI

public final class DiskIOWidget: DashboardWidget {
    public let widgetId = "disk-io"
    public let displayName = "Disk I/O"
    public let description = "Real-time disk read and write speeds"
    public let iconName = "internaldrive"
    public let category: WidgetCategory = .system
    public let requiredServices: Set<ServiceKey> = [.diskIO]
    public let supportedSizes = WidgetSizeRange(min: .size(2, 1), max: .size(8, 4))
    public let defaultSize = WidgetSize.size(4, 3)

    public let configSchema: [ConfigSchemaEntry] = []
    public let defaultColors = WidgetColors(primary: .blue, secondary: .green, tertiary: .orange)

    private let service: DiskIOService

    public init(service: DiskIOService) {
        self.service = service
    }

    @MainActor
    public func body(size: WidgetSize, config: WidgetConfig) -> any View {
        DiskIOWidgetView(service: service, isCompact: size.height <= 2, showTitle: true, isBar: size.height <= 1)
    }
}

private struct DiskIOWidgetView: View {
    @ObservedObject var service: DiskIOService
    @Environment(\.themeSettings) private var ts
    let isCompact: Bool
    // Keep the widget's name visible wherever it fits: the full header down
    // to 2 rows, a bare caption in the 1-row layout.
    let showTitle: Bool
    let isBar: Bool

    var body: some View {
        VStack(spacing: isCompact ? 6 : 12) {
            if !isCompact || (showTitle && !isBar) {
                WidgetHeader(title: "DISK I/O", color: Theme.widgetPrimary("disk-io", ts: ts, default: .blue))
            } else if showTitle {
                Text("DISK I/O")
                    .font(Theme.caption(ts))
                    .foregroundStyle(Theme.text3(ts))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Spacer(minLength: 0)

            RatePairView(
                first: .init(
                    icon: "arrow.down.circle.fill", label: "READ",
                    value: formatSpeed(service.readBytesPerSec),
                    color: Theme.widgetSecondary("disk-io", ts: ts, default: .green) ?? Theme.accentGreen
                ),
                second: .init(
                    icon: "arrow.up.circle.fill", label: "WRITE",
                    value: formatSpeed(service.writeBytesPerSec),
                    color: Theme.widgetTertiary("disk-io", ts: ts, default: .orange) ?? Theme.accentOrange
                ),
                compact: isCompact
            )

            Spacer(minLength: 0)
        }
        .padding(isCompact ? Theme.compactPadding : Theme.widgetPadding)
        .widgetCard()
    }

    private func formatSpeed(_ bytesPerSec: Double) -> String {
        if bytesPerSec < 1024 { return String(format: "%.0f B/s", bytesPerSec) }
        if bytesPerSec < 1024 * 1024 { return String(format: "%.1f KB/s", bytesPerSec / 1024) }
        if bytesPerSec < 1024 * 1024 * 1024 { return String(format: "%.1f MB/s", bytesPerSec / (1024 * 1024)) }
        return String(format: "%.2f GB/s", bytesPerSec / (1024 * 1024 * 1024))
    }
}
