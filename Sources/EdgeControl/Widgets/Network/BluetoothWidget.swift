import SwiftUI

public final class BluetoothWidget: DashboardWidget {
    public let widgetId = "bluetooth"
    public let displayName = "Bluetooth"
    public let description = "Connected Bluetooth devices with battery levels"
    public let iconName = "wave.3.right"
    public let category: WidgetCategory = .network
    public let supportedSizes = WidgetSizeRange(min: .size(3, 2), max: .size(6, 4))
    public let defaultSize = WidgetSize.size(4, 3)

    public let configSchema: [ConfigSchemaEntry] = [
        ConfigSchemaEntry(key: "showBattery", label: "Show Battery", type: .toggle, defaultValue: .bool(true)),
    ]
    public let defaultColors = WidgetColors(primary: .blue)

    private let service: BluetoothService

    public init(service: BluetoothService) {
        self.service = service
    }

    @MainActor
    public func body(size: WidgetSize, config: WidgetConfig) -> any View {
        BluetoothWidgetView(
            service: service,
            showBattery: config.bool("showBattery", default: true),
            isCompact: size.height <= 2
        )
    }
}

private struct BluetoothWidgetView: View {
    @ObservedObject var service: BluetoothService
    @Environment(\.themeSettings) private var ts
    let showBattery: Bool
    let isCompact: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: isCompact ? 6 : 10) {
            HStack(spacing: 8) {
                Image(systemName: "bluetooth")
                    .font(.system(size: (isCompact ? 16 : 22) * ts.fontScale))
                    .foregroundStyle(service.isAvailable ? Theme.widgetPrimary("bluetooth", ts: ts, default: .blue) : Theme.text3(ts))
                if !isCompact {
                    Text("Bluetooth")
                        .font(Theme.title(ts))
                        .foregroundStyle(Theme.text2(ts))
                }
                Spacer()
                let connected = service.devices.filter(\.isConnected).count
                if connected > 0 {
                    Text("\(connected)")
                        .font(Theme.label(ts))
                        .foregroundStyle(Theme.widgetPrimary("bluetooth", ts: ts, default: .blue))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Theme.widgetPrimary("bluetooth", ts: ts, default: .blue).opacity(0.15), in: Capsule())
                }
            }

            let connectedDevices = service.devices.filter(\.isConnected)

            if connectedDevices.isEmpty {
                Spacer()
                Text("No Devices")
                    .font(Theme.body(ts))
                    .foregroundStyle(Theme.text3(ts))
                    .frame(maxWidth: .infinity)
                Spacer()
            } else {
                ForEach(connectedDevices) { device in
                    HStack(spacing: 8) {
                        Image(systemName: device.icon)
                            .font(.system(size: (isCompact ? 14 : 18) * ts.fontScale))
                            .foregroundStyle(Theme.widgetPrimary("bluetooth", ts: ts, default: .blue))
                            .frame(width: 24)

                        Text(device.name)
                            .font(Theme.body(ts))
                            .foregroundStyle(Theme.text1(ts))
                            .lineLimit(1)

                        Spacer()

                        if showBattery, let battery = device.batteryLevel {
                            HStack(spacing: 4) {
                                Image(systemName: batteryIcon(battery))
                                    .font(.system(size: 14 * ts.fontScale))
                                    .foregroundStyle(batteryColor(battery))
                                Text("\(battery)%")
                                    .font(Theme.label(ts))
                                    .foregroundStyle(batteryColor(battery))
                                    .monospacedDigit()
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(isCompact ? Theme.compactPadding : Theme.widgetPadding)
        .widgetCard()
    }

    private func batteryIcon(_ level: Int) -> String {
        if level > 75 { return "battery.100" }
        if level > 50 { return "battery.75" }
        if level > 25 { return "battery.50" }
        return "battery.25"
    }

    private func batteryColor(_ level: Int) -> Color {
        if level > 50 { return Theme.accentGreen }
        if level > 20 { return Theme.accentYellow }
        return Theme.accentRed
    }
}
