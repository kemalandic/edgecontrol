import SwiftUI

public final class SSDTempWidget: DashboardWidget {
    public let widgetId = "ssd-temp"
    public let displayName = "SSD Temperature"
    public let description = "SSD temperature gauge with color-coded warning levels"
    public let iconName = "internaldrive"
    public let category: WidgetCategory = .temperature
    public let supportedSizes = WidgetSizeRange(min: .size(2, 1), max: .size(5, 4))
    public let defaultSize = WidgetSize.size(3, 3)

    public let configSchema: [ConfigSchemaEntry] = [
        ConfigSchemaEntry(key: "showLabel", label: "Show Label", type: .toggle, defaultValue: .bool(true)),
    ]
    public let defaultColors = WidgetColors(primary: .green)

    private let service: SMCService

    public init(service: SMCService) {
        self.service = service
    }

    @MainActor
    public func body(size: WidgetSize, config: WidgetConfig) -> any View {
        SSDTempWidgetView(
            service: service,
            showLabel: config.bool("showLabel", default: true),
            isBar: size.height <= 1,
            isChart: size.height == 2 && size.width >= 3,
            isCompact: size.width <= 2 && size.height <= 2
        )
    }
}

private struct SSDTempWidgetView: View {
    @ObservedObject var service: SMCService
    @Environment(\.themeSettings) private var ts
    let showLabel: Bool
    let isBar: Bool
    let isChart: Bool
    let isCompact: Bool

    private var temp: Double? { service.ssdTemperature }

    private func tempColor(_ temp: Double) -> Color {
        let primary = Theme.widgetPrimary("ssd-temp", ts: ts, default: .green)
        if temp < 45 { return primary }
        if temp < 60 { return Theme.accentYellow }
        if temp < 75 { return Theme.accentOrange }
        return Theme.accentRed
    }

    var body: some View {
        if isBar {
            barLayout
        } else if isChart {
            chartLayout
        } else {
            gaugeLayout
        }
    }

    // MARK: - Chart Layout (3x2)

    private var chartLayout: some View {
        let color = temp.map { tempColor($0) } ?? Theme.text3(ts)

        return VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text("SSD")
                    .font(Theme.font(size: ts.fontSizeCaption * 1.5, weight: .heavy, settings: ts))
                    .foregroundStyle(Theme.text3(ts))
                Spacer()
                Text(temp != nil ? String(format: "%.0f°C", temp!) : "N/A")
                    .font(Theme.font(size: ts.fontSizeLabel * 1.5, weight: .heavy, settings: ts))
                    .foregroundStyle(color)
                    .monospacedDigit()
            }

            if !service.ssdTempHistory.isEmpty {
                HistoryGraphView(
                    history: service.ssdTempHistory.map { $0 / 110.0 },
                    color: color,
                    showAxisLabels: false,
                    showCurrentDot: true
                )
                .frame(maxHeight: .infinity)
            } else {
                Spacer()
            }
        }
        .padding(Theme.compactPadding)
        .widgetCard()
    }

    private var barLayout: some View {
        let color = temp.map { tempColor($0) } ?? Theme.text3(ts)

        return HStack(spacing: 8) {
            Image(systemName: "internaldrive")
                .font(.system(size: 14 * ts.fontScale))
                .foregroundStyle(color)
            Text("SSD")
                .font(Theme.label(ts))
                .foregroundStyle(color)
            Spacer()
            Text(temp != nil ? String(format: "%.0f°C", temp!) : "N/A")
                .font(Theme.value(ts))
                .foregroundStyle(color)
                .monospacedDigit()
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: Theme.radius(ts), style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radius(ts), style: .continuous)
                .strokeBorder(color.opacity(0.2), lineWidth: 1)
        )
    }

    private var gaugeLayout: some View {
        VStack(spacing: isCompact ? 4 : 8) {
            if let temp {
                let color = tempColor(temp)

                if isCompact {
                    VStack(spacing: 2) {
                        Image(systemName: "internaldrive")
                            .font(.system(size: 18 * ts.fontScale))
                            .foregroundStyle(color)
                        Text(String(format: "%.0f°", temp))
                            .font(Theme.value(ts))
                            .foregroundStyle(color)
                            .monospacedDigit()
                    }
                } else {
                    RadialGaugeView(
                        value: temp,
                        maxValue: 100,
                        label: "SSD",
                        displayValue: String(format: "%.0f°C", temp),
                        unit: "",
                        accentColor: color,
                        showLabel: showLabel
                    )
                }
            } else {
                Image(systemName: "internaldrive")
                    .font(.system(size: 24 * ts.fontScale))
                    .foregroundStyle(Theme.text3(ts))
                Text("N/A")
                    .font(Theme.body(ts))
                    .foregroundStyle(Theme.text3(ts))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(Theme.compactPadding)
        .widgetCard()
    }
}
