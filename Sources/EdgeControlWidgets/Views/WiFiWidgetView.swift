import SwiftUI
import WidgetKit

struct WiFiWidget: Widget {
    let kind = "WiFi"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: WiFiProvider()) { entry in
            WiFiWidgetView(entry: entry)
                .containerBackground(WidgetColors.background, for: .widget)
        }
        .configurationDisplayName("WiFi Info")
        .description("SSID, signal strength, and channel")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct WiFiWidgetView: View {
    let entry: WiFiEntry

    @Environment(\.widgetFamily) var family

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "wifi")
                    .font(.system(size: 14))
                    .foregroundStyle(WidgetColors.green)
                Text("WiFi")
                    .font(.system(size: 12, weight: .heavy, design: .rounded))
                    .foregroundStyle(WidgetColors.textSecondary)
                Spacer()
                signalBars
            }

            if let ssid = entry.ssid {
                Text(ssid)
                    .font(.system(size: family == .systemSmall ? 18 : 22, weight: .bold, design: .rounded))
                    .foregroundStyle(WidgetColors.textPrimary)
                    .lineLimit(1)
            } else {
                Text("Not Connected")
                    .font(.system(size: 16, weight: .medium, design: .rounded))
                    .foregroundStyle(WidgetColors.textTertiary)
            }

            Spacer()

            if family == .systemMedium {
                HStack(spacing: 16) {
                    if let ch = entry.channel {
                        detailItem(label: "CHANNEL", value: "\(ch)")
                    }
                    if let band = entry.band {
                        detailItem(label: "BAND", value: band)
                    }
                    if let rssi = entry.signalStrength {
                        detailItem(label: "RSSI", value: "\(rssi) dBm")
                    }
                }
            }
        }
        .padding(12)
        .staleOverlay(isStale: entry.isStale, minutesAgo: entry.minutesAgo)
    }

    private var signalBars: some View {
        let bars = entry.signalStrength.map { WidgetFormatters.signalBars(rssi: $0) } ?? 0
        return HStack(spacing: 2) {
            ForEach(0..<4, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1)
                    .fill(i < bars ? WidgetColors.green : Color.white.opacity(0.15))
                    .frame(width: 4, height: CGFloat(6 + i * 3))
            }
        }
    }

    private func detailItem(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 9, weight: .heavy, design: .rounded))
                .foregroundStyle(WidgetColors.textTertiary)
            Text(value)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(WidgetColors.textSecondary)
        }
    }
}
