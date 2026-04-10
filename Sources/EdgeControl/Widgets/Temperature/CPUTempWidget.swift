import SwiftUI

public final class CPUTempWidget: DashboardWidget {
    public let widgetId = "cpu-temp"
    public let displayName = "CPU Temperature"
    public let description = "CPU temperature gauge with color-coded warning levels"
    public let iconName = "cpu"
    public let category: WidgetCategory = .temperature
    public let supportedSizes = WidgetSizeRange(min: .size(2, 1), max: .size(5, 4))
    public let defaultSize = WidgetSize.size(3, 3)

    public let configSchema: [ConfigSchemaEntry] = [
        ConfigSchemaEntry(key: "unit", label: "Unit", type: .picker, defaultValue: .string("C")),
        ConfigSchemaEntry(key: "warningThreshold", label: "Warning Threshold", type: .stepper, defaultValue: .int(85)),
    ]
    public let defaultColors = WidgetColors(primary: .cyan)

    private let service: SMCService

    public init(service: SMCService) {
        self.service = service
    }

    @MainActor
    public func body(size: WidgetSize, config: WidgetConfig) -> any View {
        TempGaugeWidgetView(
            service: service,
            widgetId: widgetId,
            sensor: .cpu,
            label: "CPU",
            defaultCoolColor: .cyan,
            isBar: size.height <= 1,
            isChart: size.height == 2 && size.width >= 3,
            isCompact: size.width <= 2 && size.height <= 2
        )
    }
}

public final class GPUTempWidget: DashboardWidget {
    public let widgetId = "gpu-temp"
    public let displayName = "GPU Temperature"
    public let description = "GPU temperature gauge with color-coded warning levels"
    public let iconName = "gpu"
    public let category: WidgetCategory = .temperature
    public let supportedSizes = WidgetSizeRange(min: .size(2, 1), max: .size(5, 4))
    public let defaultSize = WidgetSize.size(3, 3)

    public let configSchema: [ConfigSchemaEntry] = [
        ConfigSchemaEntry(key: "unit", label: "Unit", type: .picker, defaultValue: .string("C")),
        ConfigSchemaEntry(key: "warningThreshold", label: "Warning Threshold", type: .stepper, defaultValue: .int(90)),
    ]
    public let defaultColors = WidgetColors(primary: .orange)

    private let service: SMCService

    public init(service: SMCService) {
        self.service = service
    }

    @MainActor
    public func body(size: WidgetSize, config: WidgetConfig) -> any View {
        TempGaugeWidgetView(
            service: service,
            widgetId: widgetId,
            sensor: .gpu,
            label: "GPU",
            defaultCoolColor: .orange,
            isBar: size.height <= 1,
            isChart: size.height == 2 && size.width >= 3,
            isCompact: size.width <= 2 && size.height <= 2
        )
    }
}

// MARK: - Shared View

private enum TempSensor {
    case cpu, gpu
}

private struct TempGaugeWidgetView: View {
    @ObservedObject var service: SMCService
    @Environment(\.themeSettings) private var ts
    let widgetId: String
    let sensor: TempSensor
    let label: String
    let defaultCoolColor: ThemeColor
    let isBar: Bool
    let isChart: Bool
    let isCompact: Bool

    private var temp: Double? {
        switch sensor {
        case .cpu: service.cpuTemperature
        case .gpu: service.gpuTemperature
        }
    }

    private func tempColor(_ temp: Double) -> Color {
        if temp < 50 { return Theme.widgetPrimary(widgetId, ts: ts, default: defaultCoolColor) }
        if temp < 70 { return Theme.accentGreen }
        if temp < 85 { return Theme.accentYellow }
        if temp < 95 { return Theme.accentOrange }
        return Theme.accentRed
    }

    private var history: [Double] {
        switch sensor {
        case .cpu: service.cpuTempHistory
        case .gpu: service.gpuTempHistory
        }
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

    // MARK: - Bar Layout (Nx1)

    private var barLayout: some View {
        let temp = self.temp
        let color = temp.map { tempColor($0) } ?? Theme.text3(ts)

        return HStack(spacing: 8) {
            Image(systemName: sensor == .cpu ? "cpu" : sensor == .gpu ? "gpu" : "internaldrive")
                .font(.system(size: 14 * ts.fontScale))
                .foregroundStyle(color)
            Text(label)
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

    // MARK: - Chart Layout (3x2)

    private var chartLayout: some View {
        let color = temp.map { tempColor($0) } ?? Theme.text3(ts)

        return VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(label)
                    .font(Theme.font(size: ts.fontSizeCaption * 1.5, weight: .heavy, settings: ts))
                    .foregroundStyle(Theme.text3(ts))
                Spacer()
                Text(temp != nil ? String(format: "%.0f°C", temp!) : "N/A")
                    .font(Theme.font(size: ts.fontSizeLabel * 1.5, weight: .heavy, settings: ts))
                    .foregroundStyle(color)
                    .monospacedDigit()
            }

            if !history.isEmpty {
                HistoryGraphView(
                    history: history.map { $0 / 110.0 },
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

    // MARK: - Gauge Layout (2x2+)

    private var gaugeLayout: some View {
        VStack(spacing: isCompact ? 4 : 8) {
            if let temp {
                let color = tempColor(temp)

                if isCompact {
                    VStack(spacing: 2) {
                        Image(systemName: sensor == .cpu ? "cpu" : "gpu")
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
                        maxValue: 110,
                        label: label,
                        displayValue: String(format: "%.0f°C", temp),
                        unit: "",
                        accentColor: color,
                        showLabel: true
                    )
                }
            } else {
                Image(systemName: sensor == .cpu ? "cpu" : "gpu")
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
