import SwiftUI

public final class DiskIOWidget: DashboardWidget {
    public let widgetId = "disk-io"
    public let displayName = "Disk I/O"
    public let description = "Real-time disk read and write speeds"
    public let iconName = "internaldrive"
    public let category: WidgetCategory = .system
    public let requiredServices: Set<ServiceKey> = [.diskIO]
    public let supportedSizes = WidgetSizeRange(min: .size(1, 1), max: .size(8, 4))
    public let defaultSize = WidgetSize.size(4, 3)

    public let configSchema: [ConfigSchemaEntry] = []
    public let defaultColors = WidgetColors(primary: .blue, secondary: .green, tertiary: .orange)

    private let service: DiskIOService

    public init(service: DiskIOService) {
        self.service = service
    }

    @MainActor
    public func body(size: WidgetSize, config: WidgetConfig) -> any View {
        DiskIOWidgetView(
            service: service, isCompact: size.height <= 2, showTitle: true, isBar: size.height <= 1,
            isNarrow: size.width <= 1, showsHistory: size.height >= 3 && size.width >= 2)
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
    // One grid column: stacked groups under a slim caption.
    let isNarrow: Bool
    /// Tall tiles graph the last minute of reads and writes under the rates,
    /// rather than leaving the space empty.
    let showsHistory: Bool

    private var readColor: Color { Theme.widgetSecondary("disk-io", ts: ts, default: .green) ?? Theme.accentGreen }
    private var writeColor: Color { Theme.widgetTertiary("disk-io", ts: ts, default: .orange) ?? Theme.accentOrange }

    var body: some View {
        VStack(spacing: isCompact ? 6 : 12) {
            if (!isCompact || (showTitle && !isBar)) && !isNarrow {
                WidgetHeader(title: "DISK I/O", color: Theme.widgetPrimary("disk-io", ts: ts, default: .blue))
            } else if showTitle {
                // One column can't fit "DISK I/O" legibly; a short name beats
                // a microscopic one.
                Text(isNarrow ? "DISK" : "DISK I/O")
                    .font(Theme.caption(ts))
                    .foregroundStyle(Theme.text3(ts))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if !showsHistory { Spacer(minLength: 0) }

            RatePairView(
                first: .init(
                    icon: "arrow.down.circle.fill", label: "READ",
                    value: ByteRate.formatted(service.readBytesPerSec),
                    color: readColor
                ),
                second: .init(
                    icon: "arrow.up.circle.fill", label: "WRITE",
                    value: ByteRate.formatted(service.writeBytesPerSec),
                    color: writeColor
                ),
                compact: isCompact,
                vertical: isNarrow
            )

            if showsHistory {
                history
            } else {
                Spacer(minLength: 0)
            }
        }
        .padding(isCompact ? Theme.compactPadding : Theme.widgetPadding)
        .widgetCard()
    }

    /// Reads and writes on one scale (at least 1 MB/s, so idle noise stays flat).
    private var history: some View {
        let peak = max(1_048_576, (service.readHistory + service.writeHistory).max() ?? 0)
        return ZStack {
            HistoryGraphView(history: service.writeHistory.map { $0 / peak }, color: writeColor,
                             showAxisLabels: false, showCurrentDot: false)
            HistoryGraphView(history: service.readHistory.map { $0 / peak }, color: readColor,
                             showAxisLabels: false, showCurrentDot: false)
        }
        .frame(maxHeight: .infinity)
        .accessibilityLabel("Disk activity over the last minute")
    }

}
