import SwiftUI

public final class DiskIOWidget: DashboardWidget {
    public let widgetId = "disk-io"
    public let displayName = "Disk I/O"
    public let description = "Real-time disk read and write speeds"
    public let iconName = "internaldrive"
    public let category: WidgetCategory = .system
    public let requiredServices: Set<ServiceKey> = [.diskIO]
    public let supportedSizes = WidgetSizeRange(min: .size(3, 2), max: .size(8, 4))
    public let defaultSize = WidgetSize.size(4, 3)

    public let configSchema: [ConfigSchemaEntry] = []
    public let defaultColors = WidgetColors(primary: .blue, secondary: .green, tertiary: .orange)

    private let service: DiskIOService

    public init(service: DiskIOService) {
        self.service = service
    }

    @MainActor
    public func body(size: WidgetSize, config: WidgetConfig) -> any View {
        DiskIOWidgetView(service: service, isCompact: size.height <= 2)
    }
}

private struct DiskIOWidgetView: View {
    @ObservedObject var service: DiskIOService
    @Environment(\.themeSettings) private var ts
    let isCompact: Bool

    var body: some View {
        VStack(spacing: isCompact ? 6 : 12) {
            if !isCompact {
                WidgetHeader(title: "DISK I/O", color: Theme.widgetPrimary("disk-io", ts: ts, default: .blue))
            }

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.down.circle.fill")
                            .font(.system(size: (isCompact ? 14 : 18) * ts.fontScale))
                            .foregroundStyle(Theme.widgetSecondary("disk-io", ts: ts, default: .green) ?? Theme.accentGreen)
                        Text("READ")
                            .font(Theme.label(ts))
                            .foregroundStyle(Theme.text3(ts))
                    }
                    Text(formatSpeed(service.readBytesPerSec))
                        .font(Theme.value(ts))
                        .foregroundStyle(Theme.text1(ts))
                        .monospacedDigit()
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: (isCompact ? 14 : 18) * ts.fontScale))
                            .foregroundStyle(Theme.widgetTertiary("disk-io", ts: ts, default: .orange) ?? Theme.accentOrange)
                        Text("WRITE")
                            .font(Theme.label(ts))
                            .foregroundStyle(Theme.text3(ts))
                    }
                    Text(formatSpeed(service.writeBytesPerSec))
                        .font(Theme.value(ts))
                        .foregroundStyle(Theme.text1(ts))
                        .monospacedDigit()
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

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
