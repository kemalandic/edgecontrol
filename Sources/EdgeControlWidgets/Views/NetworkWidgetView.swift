import SwiftUI
import WidgetKit

struct NetworkWidget: Widget {
    let kind = "Network"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: NetworkProvider()) { entry in
            NetworkWidgetView(entry: entry)
                .containerBackground(WidgetColors.background, for: .widget)
        }
        .configurationDisplayName("Network")
        .description("Upload and download speeds")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct NetworkWidgetView: View {
    let entry: NetworkEntry

    @Environment(\.widgetFamily) var family

    var body: some View {
        VStack(alignment: .leading, spacing: family == .systemSmall ? 8 : 12) {
            HStack(spacing: 6) {
                Image(systemName: "network")
                    .font(.system(size: 14))
                    .foregroundStyle(WidgetColors.cyan)
                Text("NETWORK")
                    .font(.system(size: 12, weight: .heavy, design: .rounded))
                    .foregroundStyle(WidgetColors.textSecondary)
            }

            Spacer()

            rateRow(icon: "arrow.down.circle.fill", label: "DOWN", rate: entry.downRate, color: WidgetColors.green)
            rateRow(icon: "arrow.up.circle.fill", label: "UP", rate: entry.upRate, color: WidgetColors.orange)

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
