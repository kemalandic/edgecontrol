import SwiftUI
import WidgetKit

struct TemperatureWidget: Widget {
    let kind = "Temperature"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TemperatureProvider()) { entry in
            TemperatureWidgetView(entry: entry)
                .containerBackground(WidgetColors.background, for: .widget)
        }
        .configurationDisplayName("Temperature")
        .description("CPU, GPU, and SSD temperatures")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct TemperatureWidgetView: View {
    let entry: TemperatureEntry

    @Environment(\.widgetFamily) var family

    var body: some View {
        Group {
            switch family {
            case .systemSmall:
                smallView
            case .systemMedium:
                mediumView
            default:
                smallView
            }
        }
        .staleOverlay(isStale: entry.isStale, minutesAgo: entry.minutesAgo)
    }

    private var smallView: some View {
        VStack(spacing: 8) {
            Image(systemName: "thermometer.medium")
                .font(.system(size: 20))
                .foregroundStyle(WidgetColors.orange)

            if let cpu = entry.cpuTemp {
                Text(WidgetFormatters.temperature(cpu))
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundStyle(WidgetColors.tempColor(for: cpu))

                Text("CPU")
                    .font(.system(size: 12, weight: .heavy, design: .rounded))
                    .foregroundStyle(WidgetColors.textSecondary)
            } else {
                Text("--")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundStyle(WidgetColors.textTertiary)
            }
        }
        .padding(8)
    }

    private var mediumView: some View {
        HStack(spacing: 0) {
            tempColumn(label: "CPU", temp: entry.cpuTemp)
            Divider().background(WidgetColors.border)
            tempColumn(label: "GPU", temp: entry.gpuTemp)
            Divider().background(WidgetColors.border)
            tempColumn(label: "SSD", temp: entry.ssdTemp)
        }
        .padding(12)
    }

    private func tempColumn(label: String, temp: Double?) -> some View {
        VStack(spacing: 6) {
            Image(systemName: "thermometer.medium")
                .font(.system(size: 16))
                .foregroundStyle(temp.map { WidgetColors.tempColor(for: $0) } ?? WidgetColors.textTertiary)

            Text(temp.map { WidgetFormatters.temperature($0) } ?? "--")
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundStyle(temp.map { WidgetColors.tempColor(for: $0) } ?? WidgetColors.textTertiary)

            Text(label)
                .font(.system(size: 11, weight: .heavy, design: .rounded))
                .foregroundStyle(WidgetColors.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }
}
