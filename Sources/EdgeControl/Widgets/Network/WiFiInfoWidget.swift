import SwiftUI

public final class WiFiInfoWidget: DashboardWidget {
    public let widgetId = "wifi-info"
    public let displayName = "WiFi Info"
    public let description = "WiFi connection status, SSID, signal strength, and speed"
    public let iconName = "wifi"
    public let category: WidgetCategory = .network
    public let supportedSizes = WidgetSizeRange(min: .size(3, 2), max: .size(6, 4))
    public let defaultSize = WidgetSize.size(4, 3)

    public let configSchema: [ConfigSchemaEntry] = []
    public let defaultColors = WidgetColors(primary: .green)

    private let service: WiFiService

    public init(service: WiFiService) {
        self.service = service
    }

    @MainActor
    public func body(size: WidgetSize, config: WidgetConfig) -> any View {
        WiFiInfoWidgetView(service: service, isCompact: size.height <= 2)
    }
}

private struct WiFiInfoWidgetView: View {
    @ObservedObject var service: WiFiService
    @Environment(\.themeSettings) private var ts
    let isCompact: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: isCompact ? 6 : 10) {
            HStack(spacing: 8) {
                Image(systemName: service.isConnected ? "wifi" : "wifi.slash")
                    .font(.system(size: (isCompact ? 18 : 24) * ts.fontScale))
                    .foregroundStyle(service.isConnected ? Theme.widgetPrimary("wifi-info", ts: ts, default: .green) : Theme.accentRed)

                if !isCompact {
                    Text("WiFi")
                        .font(Theme.title(ts))
                        .foregroundStyle(Theme.text2(ts))
                }
                Spacer()

                if service.isConnected {
                    signalBars(rssi: service.signalStrength)
                }
            }

            if service.isConnected {
                Text(service.ssid ?? "Unknown")
                    .font(Theme.value(ts))
                    .foregroundStyle(Theme.text1(ts))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)

                if !isCompact {
                    HStack(spacing: 12) {
                        detailChip("SPEED", value: String(format: "%.0f Mbps", service.txRate))
                        detailChip("CH", value: "\(service.channel)")
                    }
                    if let bssid = service.bssid {
                        Text(bssid)
                            .font(Theme.micro(ts))
                            .foregroundStyle(Theme.text3(ts))
                    }
                }
            } else {
                Text("Not Connected")
                    .font(Theme.body(ts))
                    .foregroundStyle(Theme.text3(ts))
            }

            Spacer(minLength: 0)
        }
        .padding(isCompact ? Theme.compactPadding : Theme.widgetPadding)
        .widgetCard()
    }

    private func signalBars(rssi: Int) -> some View {
        HStack(spacing: 2) {
            ForEach(0..<4, id: \.self) { i in
                RoundedRectangle(cornerRadius: 2)
                    .fill(barColor(for: i, rssi: rssi))
                    .frame(width: 4, height: CGFloat(8 + i * 4))
            }
        }
    }

    private func barColor(for index: Int, rssi: Int) -> Color {
        let strength: Int
        if rssi > -50 { strength = 4 }
        else if rssi > -60 { strength = 3 }
        else if rssi > -70 { strength = 2 }
        else { strength = 1 }
        return index < strength ? Theme.widgetPrimary("wifi-info", ts: ts, default: .green) : Color.white.opacity(0.1)
    }

    private func detailChip(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(Theme.caption(ts))
                .foregroundStyle(Theme.text3(ts))
            Text(value)
                .font(Theme.body(ts))
                .foregroundStyle(Theme.text1(ts))
                .monospacedDigit()
        }
    }
}
