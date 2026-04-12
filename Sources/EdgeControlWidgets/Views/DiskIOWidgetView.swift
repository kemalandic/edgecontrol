import SwiftUI
import WidgetKit

struct DiskIOWidget: Widget {
    let kind = "DiskIO"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: DiskIOProvider()) { entry in
            DiskIOWidgetView(entry: entry)
                .containerBackground(WidgetColors.background, for: .widget)
        }
        .configurationDisplayName("Disk I/O")
        .description("Disk read and write speeds")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct DiskIOWidgetView: View {
    let entry: DiskIOEntry

    @Environment(\.widgetFamily) var family

    var body: some View {
        VStack(alignment: .leading, spacing: family == .systemSmall ? 8 : 12) {
            HStack(spacing: 6) {
                Image(systemName: "internaldrive")
                    .font(.system(size: 14))
                    .foregroundStyle(WidgetColors.purple)
                Text("DISK I/O")
                    .font(.system(size: 12, weight: .heavy, design: .rounded))
                    .foregroundStyle(WidgetColors.textSecondary)
            }

            Spacer()

            rateRow(icon: "arrow.down.circle.fill", label: "READ", rate: entry.readRate, color: WidgetColors.cyan)
            rateRow(icon: "arrow.up.circle.fill", label: "WRITE", rate: entry.writeRate, color: WidgetColors.orange)

            Spacer()
        }
        .padding(12)
        .staleOverlay(isStale: entry.isStale, minutesAgo: entry.minutesAgo)
    }

    private func rateRow(icon: String, label: String, rate: Double, color: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(color)

            if family == .systemMedium {
                Text(label)
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .foregroundStyle(WidgetColors.textTertiary)
                    .frame(width: 40, alignment: .leading)
            }

            Spacer()

            Text(WidgetFormatters.bytesPerSec(rate))
                .font(.system(size: family == .systemSmall ? 16 : 18, weight: .bold, design: .rounded))
                .foregroundStyle(WidgetColors.textPrimary)
        }
    }
}
